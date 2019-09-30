# OffsetBuffers.jl
Array buffers with growing indexing for array data streams.

Buffer counts items pushed to the end and uses counted value as index for last buffered data.

There are two types of OffsetBuffers:
- RollingBuffer - data items are stored in a circular fashion, same as CircularBuffer at DataStructures.jl package.
- SlidingBuffer - data items are stored contigiously from old to new, so you can always work with underlying array.
