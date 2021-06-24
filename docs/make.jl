using Documenter
using PowerModelsONM

import NodeJS

import Pluto
import Gumbo


const _FAST = findfirst(isequal("--fast"), ARGS) !== nothing
const _PDF = findfirst(isequal("--pdf"), ARGS) !== nothing

# compile pdf docs?
if !_PDF
    format = Documenter.HTML(
        analytics = "",
        mathengine = Documenter.MathJax(),
        prettyurls=false,
        collapselevel=2,
    )
else
    format = Documenter.LaTeX()
end

pages = [
    "Introduction" => "index.md",
    "installation.md",
    "Manual" => [
        "Getting Started" => "manual/quickguide.md",
        "The ONM Workflow" => "manual/onm_workflow.md",
        "Optimal Switch / Load shed Mathematical Model" => "manual/osw_mld_model.md",
        "Optimal Dispatch Mathematical Model" => "manual/opf_model.md",
    ],
    "Tutorials" => [
        "Beginners Guide" => "tutorials/Beginners Guide.md",
    ],
    "API Reference" => [
        "Data Handling" => "reference/data.md",
        "Main Entrypoint" => "reference/entrypoint.md",
        "Internal Functions" => "reference/internal.md",
        "IO Functions" => "reference/io.md",
        "Logging" => "reference/logging.md",
        "Optimization Problems" => "reference/prob.md",
        "Solution Statistics" => "reference/stats.md",
        "Variables and Constraints" => "reference/variable_constraint.md"
    ],
    "Developer Docs" => [
        "Contributing Guide" => "developer/contributing.md",
        "Style Guide" => "developer/style.md",
    ],
]

# Build schema documentation
try
    try
        @assert "6.0.3" == chomp(read(`jsonschema2md --version`, String))
    catch
        install_jsonschema2md_status = chomp(read(`$(NodeJS.npm_cmd()) install -g @adobe/jsonschema2md`, String))
        error(install_jsonschema2md_status)
    end

    schemas_out_dir = joinpath(dirname(pathof(PowerModelsONM)), "..", "docs", "src", "schemas")
    mkpath(schemas_out_dir)

    run_jsonschema2md_status = chomp(read(`jsonschema2md -d schemas -o $(schemas_out_dir) -x - -n`, String))

    schema_basenames = [split(file, ".")[1] for file in readdir("schemas") if endswith(file, "schema.json")]
    schema_files = collect(readdir(schemas_out_dir))

    for file in schema_files
        doc = open("docs/src/schemas/$file", "r") do io
            replace(
                replace(
                    replace(
                        read(io,String),
                        "../../../schemas/" => "https://raw.githubusercontent.com/lanl-ansi/PowerModelsONM.jl/main/models/"
                    ),
                    r"(\[.+\])?\((.+)?\s\".+\"\)" => s"\1(\2)",
                ),
                "patternproperties-\\" => "patternproperties-"
            )
        end

        open("docs/src/schemas/$file", "w") do io
            write(io, doc)
        end
    end

    schema_docs = "Schema Documentation" => [
        titlecase(join(split(bn, "_"), " ")) => "schemas/$(bn).md" for bn in schema_basenames
    ]
    push!(pages, schema_docs)
catch e
    error("json schema documentation build failed, skipping: $e")
end

# build documents
makedocs(
    modules = [PowerModelsONM],
    format = format,
    strict=false,
    sitename = "PowerModelsONM",
    authors = "David M Fobes and contributors",
    pages = pages
)

# Insert HTML rendered from Pluto.jl into tutorial stubs as iframes
if !_FAST
    ss = Pluto.ServerSession()
    client = Pluto.ClientSession(Symbol("client", rand(UInt16)), nothing)
    ss.connected_clients[client.id] = client
    for file in readdir("examples", join=true)
        if endswith(file, ".jl")
            nb = Pluto.load_notebook_nobackup(file)
            client.connected_notebook = nb
            Pluto.update_run!(ss, nb, nb.cells)
            html = Pluto.generate_html(nb)

            fileout = "docs/build/tutorials/$(basename(file)).html"
            open(fileout, "w") do io
                write(io, html)
            end

            doc = open("docs/build/tutorials/$(replace(basename(file), ".jl" => ".html"))", "r") do io
                Gumbo.parsehtml(read(io, String))
            end

            # add style for full height iframe
            style = Gumbo.HTMLElement(:style)
            style.children = Gumbo.HTMLNode[Gumbo.HTMLText("iframe { height: 100vh; width: 100%; }")]
            push!(doc.root[1], style)

            # create iframe containing Pluto.jl rendered HTML
            iframe = Gumbo.HTMLElement(:iframe)
            iframe.attributes = Dict{AbstractString,AbstractString}(
                "src" => "$(basename(file)).html",
            )

            # edit existing html to replace :article with :iframe
            doc.root[2][1][2][2] = iframe

            # Overwrite HTML
            open("docs/build/tutorials/$(replace(basename(file), ".jl" => ".html"))", "w") do io
                Gumbo.prettyprint(io, doc)
            end
        end
    end
end

# Deploy to github.io
deploydocs(
    repo = "github.com/lanl-ansi/PowerModelsDistribution.jl.git",
    push_preview = false,
    devbranch = "main",
)
