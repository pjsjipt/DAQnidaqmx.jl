using DAQnidaqmx
using Documenter

DocMeta.setdocmeta!(DAQnidaqmx, :DocTestSetup, :(using DAQnidaqmx); recursive=true)

makedocs(;
    modules=[DAQnidaqmx],
    authors="Paulo Jabardo <pjabardo@ipt.br>",
    repo="https://github.com/pjsjipt/DAQnidaqmx.jl/blob/{commit}{path}#{line}",
    sitename="DAQnidaqmx.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)
