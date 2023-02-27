module DAQnidaqmx

using DAQCore
using Dates
import NIDAQ

export NIDev, daqaddinput, daqstart, daqstop, daqread, daqacquire, daqconfig, daqconfigdev
export numchannels, daqchannels, isdaqfinished, isreading, samplesread

export NIException
export TermConfig, NIDefault, NIRSE, NINRSE, NIDiff, NIPseudoDiff

"Terminal configuration"
@enum TermConfig::Int32 NIDefault=NIDAQ.DAQmx_Val_Cfg_Default NIRSE=NIDAQ.DAQmx_Val_RSE NINRSE=NIDAQ.DAQmx_Val_NRSE NIDiff=NIDAQ.DAQmx_Val_Diff NIPseudoDiff=NIDAQ.DAQmx_Val_PseudoDiff



mutable struct NIDev <: AbstractInputDev
    devname::String
    handle::NIDAQ.TaskHandle
    sampling::DaqSamplingRate
    config::DaqConfig
    chans::DaqChannels{String}
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
    chans = DaqChannels(String[], "")
    sampling = DaqSamplingRate(-1.0, 1, now())
    config = DaqConfig()
    return NIDev(devname, handle, sampling, config, chans)
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

Just a wrapper around [`stoptask`](@ref) implementing the [`DAQCore` ](@ref) interface.
"""
function DAQCore.daqstop(dev::NIDev)
    stoptask(dev)
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
function DAQCore.daqaddinput(dev::NIDev, chans::AbstractString;
                                  names::AbstractString="", termconf=NIDefault,
                                  minval=0.0, maxval=5.0, units=NIDAQ.DAQmx_Val_Volts,
                                  customscalename="")
    
    r = NIDAQ.DAQmxCreateAIVoltageChan(dev.handle, chans, names,
                                       termconf, minval, maxval,
                                       units, customscalename)
    r != 0 && throw(NIException(r))
    
    fparam!(dev, "minval", minval)
    fparam!(dev, "maxval", maxval)
    iparam!(dev, "units",  units)
    iparam!(dev, "termconf", Int(termconf))
    sparam!(dev, "customscalename",  customscalename)
    sparam!(dev, "nichans",  chans)
    
    channames = listchannels(dev)
    
    channels = DaqChannels(channames, chans)
    dev.chans = channels
    return 
end

function DAQCore.daqaddinput(dev::NIDev, devname::AbstractString,
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

    daqaddinput(dev, ch; names=chnames, termconf=termconf,
                minval=minval, maxval=maxval,
                units=units, customscalename=customscalename)


    return
        
end


function DAQCore.numchannels(dev::NIDev)
    num = zeros(UInt32, 1)
    r = NIDAQ.DAQmxGetTaskNumChans(dev.handle, num)

    r != 0 && throw(NIException(r))

    return Int(num[1])
    
end

DAQCore.daqchannels(dev::NIDev) = daqchannels(dev.chans)

function listchannels(dev::NIDev)
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


function DAQCore.daqconfigdev(dev::NIDev; source="",
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
        rate = fparam(dev, "rate")
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

    dev.sampling = DaqSamplingRate(rate, nsamples, now())
    
    fparam!(dev, "rate", rate)
    iparam!(dev, "nsamples", nsamples)
    iparam!(dev, "samplemode", samplemode)
    iparam!(dev, "activeedge", activeedge)
    
    
    return 
                                    
end                       

DAQCore.daqconfig(dev::NIDev;kw...) = 
    daqconfigdev(dev; kw...)


function isdaqfinished(dev::NIDev)

    data = zeros(Int32,1)
    #data = reinterpret(NIDAQ.Bool32, zeros(Int32, 1))
    
    r = NIDAQ.DAQmxIsTaskDone(dev.handle, data)
    r != 0 && throw(NIException(r))
    return data[1] != 0
end

DAQCore.isreading(dev::NIDev) = !isdaqfinished(dev)

    
function DAQCore.daqstart(dev::NIDev, usethread=true)
    sampling = DaqSamplingRate(dev.sampling.rate, dev.sampling.nsamples, now())
    dev.sampling = sampling
    r = NIDAQ.DAQmxStartTask(dev.handle)
    r != 0 && throw(NIException(r))
    return
end


function DAQCore.daqread(dev::NIDev)

    nch = numchannels(dev)
    nsamples = dev.sampling.nsamples
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
    return MeasData(devname(dev), devtype(dev), dev.sampling, buffer,
                    dev.chans, fill("", nch))
    
    
end

function DAQCore.daqacquire(dev::NIDev)
    daqstart(dev)
    return daqread(dev)
end

function DAQCore.samplesread(dev::NIDev)

    data = zeros(UInt64,1)
    r = NIDAQ.DAQmxGetReadTotalSampPerChanAcquired(dev.handle, data)
    r != 0 && throw(NIException(r))

    return Int64(data[1])
end


end # module DAQnidaqmx
