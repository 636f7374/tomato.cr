module Tomato
  class Client < IO
    getter dnsResolver : Durian::Resolver
    getter timeout : TimeOut
    property wrapped : IO

    def initialize(@dnsResolver : Durian::Resolver, @wrapped : IO, @timeout : TimeOut = TimeOut.new)
    end

    def self.new(host : String, port : Int32, dnsResolver : Durian::Resolver, timeout : TimeOut = TimeOut.new)
      wrapped = Durian::TCPSocket.connect host, port, dnsResolver, timeout.connect

      new dnsResolver, wrapped, timeout
    end

    def self.new(ip_address : Socket::IPAddress, dnsResolver : Durian::Resolver, timeout : TimeOut = TimeOut.new)
      wrapped = TCPSocket.connect ip_address, timeout.connect

      new dnsResolver, wrapped, timeout
    end

    def simple_auth=(value : SimpleAuth)
      @simpleAuth = value
    end

    def simple_auth
      @simpleAuth
    end

    def authentication_methods=(value : Array(Authentication))
      @authenticationMethods = value
    end

    def authentication_methods
      @authenticationMethods || [Authentication::NoAuthentication]
    end

    def version=(value : Version)
      @version = value
    end

    def version
      @version || Version::V5
    end

    def read(slice : Bytes) : Int32
      wrapped.read slice
    end

    def write(slice : Bytes) : Nil
      wrapped.write slice
    end

    def <<(value : String) : IO
      wrapped << value

      self
    end

    def flush
      wrapped.flush
    end

    def close
      wrapped.close
    end

    def closed?
      wrapped.closed?
    end

    def buffer_close
      _wrapped = wrapped

      _wrapped.buffer_close if _wrapped.responds_to? :buffer_close
    end

    def create_remote(host : String, port : Int32) : TCPSocket?
      create_remote! host, port rescue nil
    end

    def create_remote(ip_address : ::Socket::IPAddress) : TCPSocket?
      create_remote! ip_address rescue nil
    end

    def create_remote!(host : String, port : Int32) : TCPSocket?
      return unless wrapped.is_a? IO::Memory if wrapped

      method, ip_address = Durian::Resolver.getaddrinfo! host, port, dnsResolver
      return unless _socket = create_remote! ip_address

      @wrapped = _socket
      _socket
    end

    def create_remote!(ip_address : ::Socket::IPAddress) : TCPSocket?
      return unless wrapped.is_a? IO::Memory if wrapped

      _socket = TCPSocket.new ip_address, timeout.connect
      _socket.read_timeout = timeout.read
      _socket.write_timeout = timeout.write

      @wrapped = _socket
      _socket
    end

    def connect!(ip_address : ::Socket::IPAddress, command : Command, remote_resolution : Bool = false)
      connect! wrapped, ip_address.address, ip_address.port, command, false
    end

    def connect!(host : String, port : Int32, command : Command, remote_resolution : Bool = false)
      connect! wrapped, host, port, command, remote_resolution
    end

    def connect!(socket : IO, host : String, port : Int32, command : Command, remote_resolution : Bool = false)
      handshake socket
      auth socket

      case remote_resolution
      when true
        ip_address = Tomato.to_ip_address host, port
        host = ip_address.address if ip_address
        process socket, host, port, command
      when false
        method, ip_address = Durian::Resolver.getaddrinfo! host, port, dnsResolver
        process socket, ip_address, command
      end

      establish socket
    end

    private def handshake(socket : IO)
      raise UnknownFlag.new unless _version = version

      memory = IO::Memory.new
      memory.write Bytes[_version.to_i]

      optional = authentication_methods.size
      memory.write Bytes[optional.to_i]

      authentication_methods.each { |method| memory.write Bytes[method.to_i] }

      socket.write memory.to_slice
      socket.flush
    end

    private def auth(socket : IO)
      raise UnknownFlag.new unless _version = version
      raise MalformedPacket.new unless _get_version = Tomato.get_version socket
      raise MismatchFlag.new if _get_version != _version

      raise MalformedPacket.new unless _method = Tomato.get_authentication socket
      raise MalformedPacket.new unless authentication_methods.includes? _method

      memory = IO::Memory.new

      case _method
      when Authentication::UserNamePassword
        raise UnknownFlag.new unless auth = simple_auth

        # 0x01 For Current version of UserName / Password Authentication
        # https://en.wikipedia.org/wiki/SOCKS

        memory.write Bytes[1_i32]
        memory.write Bytes[_version.to_i]

        memory.write Bytes[auth.userName.size]
        memory.write auth.userName.to_slice
        memory.write Bytes[auth.password.size]
        memory.write auth.password.to_slice

        socket.write memory.to_slice
        socket.flush

        raise MalformedPacket.new unless _get_version = Tomato.get_version socket
        raise MismatchFlag.new if _get_version != _version
        raise MalformedPacket.new unless verify = Tomato.get_verify socket
        raise AuthenticationFailed.new if verify.deny?
      end
    end

    private def process(socket, host : String, port : Int32, command : Command)
      raise UnknownFlag.new unless _version = version

      memory = IO::Memory.new
      memory.write Bytes[_version.to_i]
      memory.write Bytes[command.to_i]
      memory.write Bytes[Reserved::Nil.to_i]
      memory.write Bytes[Address::Domain.to_i]
      memory.write Bytes[host.size]

      memory.write host.to_slice
      memory.write_bytes port.to_u16, IO::ByteFormat::BigEndian

      socket.write memory.to_slice
      socket.flush
    end

    private def process(socket, ip_address, command : Command)
      raise UnknownFlag.new unless _version = version
      address_type = Tomato.to_address_type ip_address

      memory = IO::Memory.new
      memory.write Bytes[_version.to_i]
      memory.write Bytes[command.to_i]
      memory.write Bytes[Reserved::Nil.to_i]
      memory.write Bytes[address_type.to_i]

      case ip_address.family
      when .inet?
        memory.write Tomato.ipv4_address_to_bytes ip_address
      when .inet6?
        memory.write Tomato.ipv6_address_to_bytes ip_address
      end

      memory.write_bytes ip_address.port.to_u16, IO::ByteFormat::BigEndian

      socket.write memory.to_slice
      socket.flush
    end

    private def establish(socket : IO)
      raise UnknownFlag.new unless _version = version
      raise MalformedPacket.new unless _get_version = Tomato.get_version socket
      raise MismatchFlag.new if _get_version != _version

      raise MalformedPacket.new unless _get_status = Tomato.get_status socket
      raise ConnectionDenied.new unless _get_status.indicates_success?
      raise MalformedPacket.new unless reserved = Tomato.get_reserved socket

      raise MalformedPacket.new unless address_type = Tomato.get_address socket
      raise MalformedPacket.new if address_type.domain?

      Tomato.extract_ip_address address_type, socket
    end
  end
end
