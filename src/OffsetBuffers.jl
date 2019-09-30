module OffsetBuffers

export
    OffsetBuffer,
    RollingBuffer,
    SlidingBuffer,
    capacity, # counfirst, count, offset,
    isfull,
    prepare_append!,
    reset!


using CustomUnitRanges
include(CustomUnitRanges.filename_for_urange)  # defines URange

include("rolling_buffer.jl")
include("sliding_buffer.jl")

const OffsetBuffer{T} = Union{RollingBuffer{T}, SlidingBuffer{T}}

end # module
