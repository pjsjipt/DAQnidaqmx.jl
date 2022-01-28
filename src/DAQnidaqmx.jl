module DAQnidaqmx

import AbstractDAQs
import NIDAQ
using NIDAQ: devices
export NIDev, daqaddinput, daqstart, daqstop, daqread, daqacquire, daqconfig
export numchannels, daqchannels
export NIException
export TermConfig, NIDefault, NIRSE, NINRSE, NIDiff, NIPseudoDiff

@enum TermConfig::Int32 NIDefault=NIDAQ.DAQmx_Val_Cfg_Default NIRSE=NIDAQ.DAQmx_Val_RSE NINRSE=NIDAQ.DAQmx_Val_NRSE NIDiff=NIDAQ.DAQmx_Val_Diff NIPseudoDiff=NIDAQ.DAQmx_Val_PseudoDiff


mutable struct NIDev <: AbstractDAQs.AbstractDAQ
    devname::String
    handle::NIDAQ.TaskHandle
    NIDev(devname::String, handle::NIDAQ.TaskHandle) = new(devname, handle)
end


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

function NIException(code)
    msg = error_message(code)
    return NIException(code, msg)
end

    
function NIDev(devname::String="", loadmaxtask::Bool=false)

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

function stoptask(dev::NIDev)

    r = NIDAQ.DAQmxClearTask(dev.handle)

    r != 0 && throw(NIException(r))
    
end

function cleartask(dev::NIDev)

end
function daqaddinput(dev::NIDev, chans::AbstractString, channames::AbstractString="";
                     termconf=NIDiff, minval=0.0, maxval=0.0,
                     units=NIDAQ.DAQmx_Val_Volts, customscalename="")
    r = NIDAQ.DAQmxCreateAIVoltageChan(dev.handle, chans, channames,
                                       termconf, minval, maxval,
                                       units, customscalename)
    r != 0 && throw(NIException(r))
    
    return 
end

function daqaddinput(dev::NIDev, devname::AbstractString,
                     chans::AbstractVector, channames="";
                     termconf=NIDiff, s = "ai",
                     minval=0.0, maxval=0.0,
                     units=NIDAQ.DAQmx_Val_Volts, customscalename="")

    # Create a string appropriate for

    if isa(chans, UnitRange)
        println(s)
        ch = "$devname/$s$(first(chans)):$(last(chans))"
    else
        ch = join(("$devname/$s$i" for i in chans), ",")
    end
    if channames==""
        chnames = ""
    elseif isa(channames, AbstractString)
        chnames = join((channames[1]*string(c) for c in chans), ",")
    elseif isa(channames, AbstractVector)
        #if length(channames) == length(chans)
        chnames = join(channames, ",")
    else
        throw("channames: $channames. Illegal format!")
    end

    daqaddinput(dev, ch, chnames, termconf=termconf, minval=minval, maxval=maxval,
                units=units, customscalename=customscalename)

    return
        
end

function numchannels(dev::NIDev)
    num = zeros(UInt32, 1)
    r = NIDAQ.DAQmxGetTaskNumChans(dev.handle, num)

    r != 0 && throw(NIException(r))

    return Int(num[1])
    
end

function daqchannels(dev::NIDev)
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


function daqconfig(dev::NIDev; rate=100.0, nsamples=1,
                       source="",
                       samplemode=NIDAQ.DAQmx_Val_FiniteSamps,
                       activeedge=NIDAQ.DAQmx_Val_Rising)

    nsamples = UInt64(nsamples)

    r = NIDAQ.DAQmxCfgSampClkTiming(dev.handle, source, rate,
                                    activeedge, samplemode, nsamples)
    
    r != 0 && throw(NIException(r))

    return 
                                    
end                       

function isdaqfinished(dev::NIDev)
#    b = zeros(In
    
end

function daqstart(dev::NIDev, usethread=true)
    
end

end
