# OffsetBuffers.jl

## Installation
```julia
]add https://github.com/sairus7/OffsetBuffers.jl.git
```

## Description
Buffer counts items pushed to the end and uses counted value as index for last buffered items.

There are two types of `OffsetBuffers`:
- `RollingBuffer` - data items are stored in a circular fashion, same as CircularBuffer at DataStructures.jl package.
- `SlidingBuffer` - data items are stored contigiously in memory from old to new, so you can always work with underlying array.

Both types behave the same way, only differing in its internal representation.

```julia
julia> buf = RollingBuffer{Int}(5)
0-element RollingBuffer{Int64} with indices OffsetBuffers.URange(1,0)

julia> append!(buf, [10, 20, 30])
3-element RollingBuffer{Int64} with indices OffsetBuffers.URange(1,3):
 10
 20
 30

julia> append!(buf, [40, 50])
5-element RollingBuffer{Int64} with indices OffsetBuffers.URange(1,5):
 10
 20
 30
 40
 50

julia> append!(buf, [60, 70])
5-element RollingBuffer{Int64} with indices OffsetBuffers.URange(4,8):
 30
 40
 50
 60
 70
 
julia> firstindex(buf)
3

julia> buf[3] # == first(buf)
30

julia> lastindex(buf)
7

julia> buf[7] # == last(buf)
70

```
