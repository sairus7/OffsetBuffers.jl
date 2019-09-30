using OffsetBuffers
using Test
# using Random
# using Serialization

@test [] == detect_ambiguities(Base, Core, OffsetBuffers)

tests = [
         "rolling_buffer",
         "sliding_buffer",
        ]

if length(ARGS) > 0
    tests = ARGS
end

@testset "OffsetBuffers" begin

for t in tests
    fp = joinpath(dirname(@__FILE__), "test_$t.jl")
    println("$fp ...")
    include(fp)
end

end # @testset
