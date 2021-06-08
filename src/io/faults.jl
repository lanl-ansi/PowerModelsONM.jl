""
function parse_faults(faults_file::String)::Dict{String,Any}
    JSON.parsefile(faults_file)
end
