import struct NIOCore.ByteBuffer

protocol ByteBufferConsumer {
  mutating func consumeReadableBytes(of buffer: ByteBuffer) async throws
  mutating func finishConsumingBytes() async throws
}
