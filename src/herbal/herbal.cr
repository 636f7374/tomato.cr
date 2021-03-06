module Herbal
  enum Authentication : UInt8
    NoAuthentication = 0_u8
    GSSAPI           = 1_u8
    UserNamePassword = 2_u8
  end

  enum Version : UInt8
    V5 = 5_u8
  end

  enum Address : UInt8
    Ipv4   = 1_u8
    Domain = 3_u8
    Ipv6   = 4_u8
  end

  enum Command : UInt8
    TCPConnection = 1_u8
    TCPBinding    = 2_u8
    AssociateUDP  = 3_u8
  end

  enum Status : UInt8
    IndicatesSuccess       = 0_u8
    ConnectFailed          = 1_u8
    ConnectionNotAllowed   = 2_u8
    NetworkUnreachable     = 3_u8
    HostUnreachable        = 4_u8
    ConnectionDenied       = 5_u8
    TTLTimeOut             = 6_u8
    UnsupportedCommand     = 7_u8
    UnsupportedAddressType = 8_u8
    Undefined              = 9_u8
  end

  enum Verify : UInt8
    Pass =   0_u8
    Deny = 255_u8
  end

  enum Reserved : UInt8
    Nil = 0_u8
  end

  class UnknownFlag < Exception
  end

  class MalformedPacket < Exception
  end

  class UnEstablish < Exception
  end

  class UnknownDNSResolver < Exception
  end

  class MismatchFlag < Exception
  end

  class AuthenticationFailed < Exception
  end

  class ConnectionDenied < Exception
  end

  class BadDestinationAddress < Exception
  end

  class AuthenticationEntry
    property userName : String
    property password : String?

    def initialize(@userName : String, @password : String?)
    end
  end

  class TimeOut
    property read : Int32
    property write : Int32
    property connect : Int32

    def initialize(@read : Int32 = 30_i32, @write : Int32 = 30_i32, @connect : Int32 = 10_i32)
    end
  end

  class DestinationAddress
    property host : String
    property port : Int32

    def initialize(@host : String, @port : Int32)
    end
  end

  def self.empty_io : IO::Memory
    memory = IO::Memory.new 0_i32
    memory.close

    memory
  end

  def self.to_ip_address(host : String, port : Int32)
    ::Socket::IPAddress.new host, port rescue nil
  end

  def self.get_optional!(io : IO) : Int32?
    buffer = uninitialized UInt8[1_i32]
    length = io.read buffer.to_slice

    return unless _length = length
    return if _length.zero?

    optional = buffer.to_slice[0_i32]
    return if optional.zero?
    return if 3_u8 < optional

    optional.to_i32
  end

  def self.unspecified_ip_address
    ::Socket::IPAddress.new ::Socket::IPAddress::UNSPECIFIED, 0_i32
  end

  def self.to_address_type(ip_address : ::Socket::IPAddress)
    return Address::Ipv6 if ip_address.family.inet6?

    Address::Ipv4
  end

  def self.ipv4_address_to_bytes(ip_address : ::Socket::IPAddress) : Bytes
    buffer = IO::Memory.new 4_i32

    split = ip_address.address.split "."
    split.each { |part| buffer.write Bytes[part.to_u8] }

    buffer.to_slice
  end

  def self.extract_domain!(io : IO) : DestinationAddress?
    buffer = uninitialized UInt8[1_i32]
    length = io.read buffer.to_slice

    return unless length
    return if length.zero?

    length = buffer.to_slice[0_i32]
    memory = IO::Memory.new length
    length = IO.copy io, memory, length

    return unless length
    return if length.zero?

    domain = String.new memory.to_slice
    port = io.read_bytes UInt16, IO::ByteFormat::BigEndian
    return unless _port = port

    DestinationAddress.new domain, port.to_i32
  end

  def self.extract_ip_address!(address_type : Address, io : IO) : ::Socket::IPAddress?
    case address_type
    when .ipv6?
      return unless ip_address = ::Socket::IPAddress.ipv6_from_io io
      return unless port = io.read_bytes UInt16, IO::ByteFormat::BigEndian

      ::Socket::IPAddress.new ip_address.address, port.to_i32
    when .ipv4?
      return unless ip_address = ::Socket::IPAddress.ipv4_from_io io
      return unless port = io.read_bytes UInt16, IO::ByteFormat::BigEndian

      ::Socket::IPAddress.new ip_address.address, port.to_i32
    end
  end

  {% for name in ["version", "command", "reserved", "address", "authentication", "verify", "status"] %}
  def self.get_{{name.id}}!(io : IO) : {{name.capitalize.id}}?
    buffer = uninitialized UInt8[1_i32]
    length = io.read buffer.to_slice

    return unless _length = length
    return if _length.zero?

    {{name.capitalize.id}}.from_value? buffer.to_slice[0_i32].to_i32
  end
  {% end %}

  {% for name in ["username", "password"] %}
  def self.get_{{name.id}}!(io : IO) : String?
    buffer = uninitialized UInt8[1_i32]
    length = io.read buffer.to_slice

    return unless _length = length
    return if _length.zero?

    {{name.id}}_length = buffer.to_slice[0_i32]
    return if {{name.id}}_length.zero?

    memory = IO::Memory.new {{name.id}}_length
    IO.copy io, memory, {{name.id}}_length

    String.new memory.to_slice
  end
  {% end %}
end
