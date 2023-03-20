using Documenter
using PowerModelsONM

# imports to build pluto notebooks
import Pluto
import Gumbo

# Command-line arguments
const _FAST = findfirst(isequal("--fast"), ARGS) !== nothing
const _PDF = findfirst(isequal("--pdf"), ARGS) !== nothing

# compile html or pdf docs?
if !_PDF
    format = Documenter.HTML(
        analytics = "",
        mathengine = Documenter.MathJax(),
        prettyurls=false,
        collapselevel=2,
    )
else
    format = Documenter.LaTeX(platform="docker")
end

# Pages of the documentation

schema_pages = [
    "output.schema" => "schemas/output.schema.md",
    "settings.schema" => "schemas/input-settings.schema.md",
    "events.schema" => "schemas/input-events.schema.md",
    "faults.schema" => "schemas/input-faults.schema.md",
    "runtime-arguments.schema" => "schemas/input-runtime_arguments.schema.md",
]

pages = [
    "Introduction" => "index.md",
    "installation.md",
    "Manual" => [
        "Getting Started" => "manual/quickguide.md",
        "The ONM Workflow" => "manual/onm_workflow.md",
        "Optimal Switch / Load shed Mathematical Model" => "manual/mld_model.md",
        "Optimal Dispatch Mathematical Model" => "manual/opf_model.md",
        "Exporting with GraphML" => "manual/graphml_export.md",
    ],
    "Tutorials" => [
        "Beginners Guide" => "tutorials/Beginners Guide.md",
        "Block MLD Basic Example" => "tutorials/Block MLD Basic Example.md",
        "JuMP Model by Hand - MLD-Block Example" => "tutorials/JuMP Model by Hand - MLD-Block.md",
        "JuMP Model by Hand - MLD-Block Scenario Example" => "tutorials/JuMP Model by Hand - MLD-scenario.md",
        "Use Case Examples" => "tutorials/Use Case Examples.md",
    ],
    "API Reference" => [
        "Base functions" => "reference/base.md",
        "Data Handling" => "reference/data.md",
        "GraphML Functions" => "reference/graphml.md",
        "Main Entrypoint" => "reference/entrypoint.md",
        "Internal Functions" => "reference/internal.md",
        "IO Functions" => "reference/io.md",
        "Logging" => "reference/logging.md",
        "Optimization Problems" => "reference/prob.md",
        "Solution Statistics" => "reference/stats.md",
        "Variables and Constraints" => "reference/variable_constraint.md",
        "Types" => "reference/types.md",
    ],
    "Schemas" => schema_pages,
    "Developer Docs" => [
        "Contributing Guide" => "developer/contributing.md",
        "Style Guide" => "developer/style.md",
        "Roadmap" => "developer/roadmap.md",
    ],
]

# build documents
makedocs(
    format = format,
    strict=false,
    sitename = "PowerModelsONM",
    authors = "David M Fobes and contributors",
    pages = pages
)


# Build schema documentation
try
    # imports to build schema documentation
    import PyCall
    import Conda

    Conda.pip_interop(true)
    Conda.pip("install", "json-schema-for-humans")
    jsfhgc = PyCall.pyimport("json_schema_for_humans.generation_configuration")
    jsfhg = PyCall.pyimport("json_schema_for_humans.generate")

    schemas_in_dir = joinpath(dirname(pathof(PowerModelsONM)), "..", "schemas")
    schemas_out_dir = joinpath(dirname(pathof(PowerModelsONM)), "..", "docs", "build", "schemas")
    mkpath(schemas_out_dir)

    schema_files = replace.(basename.([x.second for x in schema_pages]), ".md"=>".json")

    for file in schema_files
        jsfhg.generate_from_filename(joinpath(schemas_in_dir, file), joinpath(schemas_out_dir, replace(file, ".json"=>".iframe.html")))

        doc = open(joinpath(schemas_out_dir, replace(file, ".json"=>".html")), "r") do io
            Gumbo.parsehtml(read(io, String))
        end

        # add style for full height iframe
        style = Gumbo.HTMLElement(:style)
        style.children = Gumbo.HTMLNode[Gumbo.HTMLText("iframe { height: 100vh; width: 100%; }")]
        push!(doc.root[1], style)

        # create iframe containing Pluto.jl rendered HTML
        iframe = Gumbo.HTMLElement(:iframe)
        iframe.attributes = Dict{AbstractString,AbstractString}(
            "src" => "$(replace(file, ".json"=>".iframe.html"))",
        )

        # edit existing html to replace :article with :iframe
        doc.root[2][1][2][2] = iframe

        # Overwrite HTML
        open(joinpath(schemas_out_dir, replace(file, ".json"=>".html")), "w") do io
            Gumbo.prettyprint(io, doc)
        end
    end
catch e
    @warn "json schema documentation build failed, skipping: $e"
end


# Insert HTML rendered from Pluto.jl into tutorial stubs as iframes
if !_FAST
    @info "rendering pluto notebooks for static documentation"
    ss = Pluto.ServerSession()
    client = Pluto.ClientSession(Symbol("client", rand(UInt16)), nothing)
    ss.connected_clients[client.id] = client
    for file in readdir("examples", join=true)
        if endswith(file, ".jl")
            @info "rendering '$(file)' with pluto"
            nb = Pluto.load_notebook_nobackup(file);
            client.connected_notebook = nb;
            Pluto.update_run!(ss, nb, nb.cells);
            html = Pluto.generate_html(nb; binder_url_js="undefined");

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
    repo = "github.com/lanl-ansi/PowerModelsONM.jl.git",
    push_preview = false,
    devbranch = "main",
)
