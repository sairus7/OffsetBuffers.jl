@testset "SlidingBuffer" begin

    @testset "Core Functionality" begin
        buf = SlidingBuffer{Int}(5)
        @testset "When empty" begin
            @test length(buf) == 0
            @test capacity(buf) == 5
            @test_throws BoundsError first(buf)
            @test isempty(buf) == true
            @test isfull(buf) == false
            @test eltype(buf) == Int
            @test eltype(typeof(buf)) == Int
        end

        @testset "With 1 element" begin
            push!(buf, 1)
            @test length(buf) == 1
            @test capacity(buf) == 5
            @test isfull(buf) == false
        end

        @testset "Appending many elements" begin
            # append!(buf, 2:8) for offset buffers you cannot in one operation append more elements than buffer length.
            append!(buf, 2:5)
            append!(buf, 6:8)
            @test length(buf) == capacity(buf)
            @test size(buf) == (length(buf),)
            @test isempty(buf) == false
            @test isfull(buf) == true
            @test convert(Array, buf) == Int[4,5,6,7,8]
        end

        @testset "getindex" begin
            @test buf[4] == 4
            @test buf[5] == 5
            @test buf[6] == 6
            @test buf[7] == 7
            @test buf[8] == 8
            @test_throws BoundsError buf[3]
            @test_throws BoundsError buf[3:6]
            @test_throws BoundsError buf[9]
            @test_throws BoundsError buf[6:9]
            @test buf[6:7] == Int[6,7]
            @test buf[[4,8]] == Int[4,8]
        end

        @testset "setindex" begin
            buf[6] = 999
            @test convert(Array, buf) == Int[4,5,999,7,8]
        end
    end

    @testset "other constructor" begin
        buf = SlidingBuffer(10)
        @test length(buf) == 0
        @test typeof(buf) <: SlidingBuffer{Any}
    end

    @testset "pushfirst" begin
        buf = SlidingBuffer{Int}(5)  # New, empty one for full test coverage
        for i in -5:5
            pushfirst!(buf, i)
        end
        arr = convert(Array, buf)
        @test arr == Int[5, 4, 3, 2, 1]
        for (idx, n) in enumerate(5:1)
            @test arr[idx] == n
        end
    end

    @testset "Issue 429" begin
        buf = SlidingBuffer{Int}(5)
        map(x -> pushfirst!(buf, x), 1:8)
        pop!(buf)
        pushfirst!(buf, 9)
        @test length(buf.buffer) == buf.capacity
        arr = convert(Array, buf)
        @test arr == Int[9, 8, 7, 6, 5]
    end

    @testset "Issue 379" begin
        buf = SlidingBuffer{Int}(5)
        pushfirst!(buf, 1)
        @test buf == [1]
        pushfirst!(buf, 2)
        @test buf == [2, 1]
    end

    @testset "empty!" begin
        buf = SlidingBuffer{Int}(5)
        push!(buf, 13)
        empty!(buf)
        @test length(buf) == 0
    end

    @testset "pop!" begin
        buf = SlidingBuffer{Int}(5)
        for i in 0:5    # one extra to force wraparound
            push!(buf, i)
        end
        for j in 5:-1:1
            @test pop!(buf) == j
            @test convert(Array, buf) == collect(1:j-1)
        end
        @test isempty(buf)
        @test_throws ArgumentError pop!(buf)
    end

    @testset "popfirst!" begin
        buf = SlidingBuffer{Int}(5)
        for i in 0:5    # one extra to force wraparound
            push!(buf, i)
        end
        for j in 1:5
            @test popfirst!(buf) == j
            @test convert(Array, buf) == collect(j+1:5)
        end
        @test isempty(buf)
        @test_throws ArgumentError popfirst!(buf)
    end

    @testset "fill!" begin
        @testset "fill an empty buffer" begin
            buf = SlidingBuffer{Int}(3)
            fill!(buf, 42)
            @test Array(buf) == [42, 42, 42]
        end
        @testset "fill a non empty buffer" begin
            buf = SlidingBuffer{Int}(3)
            push!(buf, 21)
            fill!(buf, 42)
            @test Array(buf) == [21, 42, 42]
        end
    end

    @testset "Growing indexing" begin
        @testset "push / pop with growing indexes" begin
            buf = SlidingBuffer{Int}(5)
            for i=1:8
                push!(buf, i)
            end

            @test firstindex(buf) == first(buf) == 4
            @test lastindex(buf) == last(buf) == 8

            @test Array(buf) == [4,5,6,7,8]

            for i=4:5
                popfirst!(buf)
            end

            @test firstindex(buf) == first(buf) == 6
            @test lastindex(buf) == last(buf) == 8

            @test length(buf) == 3
            @test Array(buf) == [6,7,8]
        end
        @testset "append with growing indexes" begin
            buf = SlidingBuffer{Int}(10)
            append!(buf, 1:10)

            append!(buf, 11:17)

            @test length(buf) == 10

            @test firstindex(buf) == first(buf) == 8
            @test lastindex(buf) == last(buf) == 17

            @test Array(buf) == 8:17

            for i = 8:12
                popfirst!(buf)
            end

            @test length(buf) == 5

            @test firstindex(buf) == first(buf) == 13
            @test lastindex(buf) == last(buf) == 17

            @test Array(buf) == 13:17
        end
    end

end
