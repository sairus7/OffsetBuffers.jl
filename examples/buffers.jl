N = 100
alldata = collect(1:1.0:N)

chunk = 10 # current chunk len to feed the buffer
prev_len = 20 # amount of previous data to hold in buffer
buflen = chunk + prev_len

buf = RollingBuffer{Float64}(buflen)

for i = 1 : chunk : N-chunk+1
    push!(buf, view(alldata, i:i+chunk-1))
    println("Iteration $i | data feed: $(i:i+chunk-1) | buffered data: $(firstindex(buf):lastindex(buf))")
end

same_index = map(i-> buf[i] == alldata[i], eachindex(buf)) |> all

if same_index
    println("Buffer hold the same indexes for the last elenements of the original data array.")
end
