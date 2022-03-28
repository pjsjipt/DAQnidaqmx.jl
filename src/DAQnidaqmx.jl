module DAQnidaqmx

using AbstractDAQs
using Dates
import NIDAQ

export NIDev, daqaddinput, daqstart, daqstop, daqread, daqacquire, daqconfig, daqconfigdev
export numchannels, daqchannels, isdaqfinished, isreading, samplesread

export NIException
export TermConfig, NIDefault, NIRSE, NINRSE, NIDiff, NIPseudoDiff

"Terminal configuration"
@enum TermConfig::Int32 NIDefault=NIDAQ.DAQmx_Val_Cfg_Default NIRSE=NIDAQ.DAQmx_Val_RSE NINRSE=NIDAQ.DAQmx_Val_NRSE NIDiff=NIDAQ.DAQmx_Val_Diff NIPseudoDiff=NIDAQ.DAQmx_Val_PseudoDiff


mutable struct NIDev <: AbstractDAQs.AbstractDAQ
    devname::String
    handle::NIDAQ.TaskHandle
    rate::Float64
    nsamples::Int64
    time::DateTime
    conf::DAQConfig
    chanidx::Dict{String,Int}
    NIDev(devname::String, handle::NIDAQ.TaskHandle) = new(devname, handle, -1.0, -1, now(),
                                                           DAQConfig(devname=devname),
                                                           Dict{String,Int}())
end

"""
`error_message(errnum, buflen)`

Return an error/warning message from its code.
"""
function error_message(errnum, buflen=1000)

    buf = zeros(UInt8, buflen)

    r = NIDAQ.DAQmxGetErrorString(errnum, buf, buflen)
    if r != 0
        return "$errnum: unknown error"
    end
    
    idx = findfirst(iszero, buf)
    idx1 =  isnothing(idx) ? buflen : idx-1
    return String(buf[1:idx1])
end

struct NIException <: Exception
    code::Int
    msg::String
end

"""
`NIException(code)`

Returns an `Exception` object specific for NIDAQmx. From a numeric code it 
returns a description of the exception.
"""
function NIException(code)
    msg = error_message(code)
    return NIException(code, msg)
end


"""
`NIDev(devname, loadmaxtask=false)`

Creates a device that handles NIDAQmx data acquisition. 
In the parlance used by NIDAQmx, it creates a task.

NI has tools such as NI MAX that can handle the creation and configuration of tasks. 
With argument `loadmaxtask=true` these tasks can be used directly.

The device name (`devname`) is the task name to be used by NIDAQmx.

"""
function NIDev(devname::String, loadmaxtask::Bool=false)

    th = Ref(NIDAQ.TaskHandle(0))
    if !loadmaxtask
        r = NIDAQ.DAQmxCreateTask(devname, th)
        r != 0 && throw(NIException(r))
        handle = th[]
    else
        r = NIDAQ.DAQmxLoadTask(devname, th)
        r != 0 && throw(NIException(r))
        handle = th[]
    end
    
    return NIDev(devname, handle)
end

"""
`stoptask(dev)`

Stops the execution of a task. It calls NIDAQmx function `DAQmxStopTask`.
"""
function stoptask(dev::NIDev)

    r = NIDAQ.DAQmxStopTask(dev.handle)

    r != 0 && throw(NIException(r))
    
end

"""
`cleartask(dev)`

Clears a task. It calls NIDAQmx function `DAQmxClearTask`. After calling this function, 
the task must be reconfigured.
"""
function cleartask(dev::NIDev)

    r = NIDAQ.DAQmxClearTask(dev.handle)

    r != 0 && throw(NIException(r))
    
end


"""
`daqstop(dev)`

Just a wrapper around [`stoptask`](@ref) implementing the [`AbstractDAQs` ](@ref) interface.
"""
function AbstractDAQs.daqstop(dev::NIDev)
    stoptask(dev)
end

"""
`setchanidx!(dev::NIDev)`

Reads the channel names and sets up `chanidx` Dict field that
maps from channel names (`String`) to index (Integer)



"""
function setchanidx!(dev::NIDev)

    chn = daqchannels(dev)
    chd = Dict{String,Int}()
    for (i,c) in enumerate(chn)
        chd[c] = i
    end
    dev.chanidx = chd
    return

end


"""
`daqaddinput(dev::NIDev, chans, names; termconf, minval, maxmval, units, customscale)`

Adds input to `NIDev` object. For now it handles only AI Voltage channels. In the future, 
more specific input types will be implemented.

## Arguments
 * `chans`: Physical channels usually something like "Dev1/ai0". See NIDAQmx documentation.
 * `names`: Channel names, if "" the physical names are used. 
 * `termconf`: Terminal configuration (RSE, NRSE, Differential, Pseudodifferential). See [`TermConf`] and NIDAQmx docs for further information
 * `minval` and `maxval`:

"""
function AbstractDAQs.daqaddinput(dev::NIDev, chans::AbstractString; names::AbstractString="",
                     termconf=NIDefault, minval=0.0, maxval=5.0,
                     units=NIDAQ.DAQmx_Val_Volts, customscalename="")
    r = NIDAQ.DAQmxCreateAIVoltageChan(dev.handle, chans, names,
                                       termconf, minval, maxval,
                                       units, customscalename)
    r != 0 && throw(NIException(r))
    
    dev.conf.fpars["minval"] = minval
    dev.conf.fpars["minval"] = maxval
    dev.conf.ipars["units"] = units
    dev.conf.ipars["termconf"] = Int(termconf)
    dev.conf.spars["customscalename"] = customscalename
    dev.conf.spars["nichans"] = chans
    
    setchanidx!(dev)
    
    return 
end

function AbstractDAQs.daqaddinput(dev::NIDev, devname::AbstractString,
                     chans::AbstractVector{<:Integer}; names="",
                     termconf=NIDiff, s = "ai",
                     minval=0.0, maxval=5.0,
                     units=NIDAQ.DAQmx_Val_Volts, customscalename="")

    # Create a string appropriate for

    if isa(chans, UnitRange)
        ch = "$devname/$s$(first(chans)):$(last(chans))"
    else
        ch = join(("$devname/$s$i" for i in chans), ",")
    end
    if names==""
        chnames = ""
    elseif isa(names, AbstractString)
        chnames = join((names[1]*string(c) for c in chans), ",")
    elseif isa(names, AbstractVector)
        #if length(names) == length(chans)
        chnames = join(names, ",")
    else
        throw("names: $names. Illegal format!")
    end
    daqaddinput(dev, ch; names=chnames, termconf=termconf, minval=minval, maxval=maxval,
                units=units, customscalename=customscalename)

    setchanidx!(dev)

    return
        
end

function AbstractDAQs.numchannels(dev::NIDev)
    num = zeros(UInt32, 1)
    r = NIDAQ.DAQmxGetTaskNumChans(dev.handle, num)

    r != 0 && throw(NIException(r))

    return Int(num[1])
    
end

function AbstractDAQs.daqchannels(dev::NIDev)
    nch = numchannels(dev)

    nperch = 30 # Number of characters per channel.
    buflen = nperch * nch
    buf = zeros(UInt8, buflen)
    r = NIDAQ.DAQmxGetTaskChannels(dev.handle, buf, buflen)

    r != 0 && throw(NIException(r))

    idx = findfirst(iszero, buf)
    idx1 =  isnothing(idx) ? buflen : idx-1
    s = String(buf[1:idx1])
    return [strip(ch) for ch in split(s, ',')]
end


function AbstractDAQs.daqconfigdev(dev::NIDev; source="",
                       samplemode=NIDAQ.DAQmx_Val_FiniteSamps,
                       activeedge=NIDAQ.DAQmx_Val_Rising, kw...)

    
    if haskey(kw, :rate) && haskey(kw, :dt)
        error("Parameters `rate` and `dt` can not be specified simultaneously!")
    elseif haskey(kw, :rate) || haskey(kw, :dt)
        if haskey(kw, :rate)
            rate = kw[:rate]
        else
            dt = kw[:dt]
            rate = 1/dt 
        end
    else
        rate = dev.conf.fpars["rate"]
    end


    if haskey(kw, :nsamples) && haskey(kw, :time)
        error("Parameters `nsamples` and `time` can not be specified simultaneously!")
    elseif haskey(kw, :nsamples) || haskey(kw, :time)
        if haskey(kw, :nsamples)
            nsamples = UInt64(kw[:nsamples])
        else
            tt = kw[:time]
            dt = 1/rate
            nsamples = round(UInt64, tt / dt)
        end
    else
        nsamples = UInt64(dev.conf.ipars("nsamples"))
    end    

    r = NIDAQ.DAQmxCfgSampClkTiming(dev.handle, source, rate,
                                    activeedge, samplemode, nsamples)
    r != 0 && throw(NIException(r))

    dev.rate = rate
    dev.nsamples = nsamples
    dev.conf.fpars["rate"] = rate
    dev.conf.ipars["nsamples"] = nsamples
    dev.conf.ipars["samplemode"] = samplemode
    dev.conf.ipars["activeedge"] = activeedge
    
    return 
                                    
end                       

function AbstractDAQs.daqconfig(dev::NIDev; source="",
                                samplemode=NIDAQ.DAQmx_Val_FiniteSamps,
                                activeedge=NIDAQ.DAQmx_Val_Rising, kw...)
    daqconfigdev(dev; source=source, samplemode=samplemode, activeedge=activeedge, kw...)
end


function AbstractDAQs.isdaqfinished(dev::NIDev)

    data = zeros(Int32,1)
    #data = reinterpret(NIDAQ.Bool32, zeros(Int32, 1))
    
    r = NIDAQ.DAQmxIsTaskDone(dev.handle, data)
    r != 0 && throw(NIException(r))
    return data[1] != 0
end

AbstractDAQs.isreading(dev::NIDev) = !isdaqfinished(dev)

    
function AbstractDAQs.daqstart(dev::NIDev, usethread=true)
    r = NIDAQ.DAQmxStartTask(dev.handle)
    r != 0 && throw(NIException(r))
    dev.time = now()
    return
end


function AbstractDAQs.daqread(dev::NIDev)

    nch = numchannels(dev)
    nsamples = dev.nsamples
    buffer = zeros(Float64, nch, nsamples)
    fm1 =  Int32[NIDAQ.DAQmx_Val_GroupByScanNumber]
    fm =  reinterpret(NIDAQ.Bool32, fm1)[1]
    nsr = Int32[1]

    # Wait for reading to end:
    while !isdaqfinished(dev)
        sleep(0.05)
    end
    
    r = NIDAQ.DAQmxReadAnalogF64(dev.handle, -1, -1.0, fm, buffer, nsamples*nch, nsr,
                                 Ptr{NIDAQ.Bool32}(0))
    r != 0 && throw(NIException(r))

    stoptask(dev)
    
    return MeasData{Matrix{Float64},Int}(devname(dev), devtype(dev), dev.time,
                                         dev.rate, buffer, 0, dev.chanidx)
    
end

function AbstractDAQs.daqacquire(dev::NIDev)
    daqstart(dev)
    return daqread(dev)
end

function AbstractDAQs.samplesread(dev::NIDev)

    data = zeros(UInt64,1)
    r = NIDAQ.DAQmxGetReadTotalSampPerChanAcquired(dev.handle, data)
    r != 0 && throw(NIException(r))

    return Int64(data[1])
end


end # module DAQnidaqmx
