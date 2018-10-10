
# returns a julia centric version of mujoco's model and data fields
# that allows direct access to Ptr array fields as julia vectors
function mapmodel(pm::Ptr{mjModel})
   c_model= unsafe_load(pm)
   mapmodel(c_model, pm)
end
function mapmodel(c_model::mjModel, pm::Ptr{mjModel})
   margs = Vector{Any}()

   m_fields = fieldnames(jlModel)[2:end] # drop :m pointer
   m_sizes = getmodelsize(c_model)
   jminfo = structinfo(jlModel)
   maxmodelmemptr = convert(UInt64, getfield(c_model, :names))
   for f in m_fields
      adr = convert(UInt64, getfield(c_model, f))
      if adr == 0x0 || adr > maxmodelmemptr # bad pointer
         m_off, m_type = jminfo[f]
         push!(margs, m_type(0) )
      else
         raw = wrap_array(getfield(c_model, f), Int(m_sizes[f][1]), Int(m_sizes[f][2]))
         push!(margs, raw)
      end
   end
   return jlModel(pm, margs...)
end
function wrap_array(p, s1::Int, s2::Int)
   len = s1 * s2 
   raw = unsafe_wrap(Array, p, len)

   if s2 > 1
      raw = reshape(raw, s2, s1)
   end
   return raw
end
function mapdata(pm::Ptr{mjModel}, pd::Ptr{mjData}) 
   c_model = unsafe_load(pm)
   mapdata(c_model, pd)
end
function mapdata(c_model::mjModel, pd::Ptr{mjData}) 
   c_data = unsafe_load(pd)

   dargs = Vector{Any}()

   d_fields = fieldnames(jlData)[2:end] # drop :d pointer
   d_sizes = getdatasize(c_model, c_data)
   for f in d_fields
      raw = wrap_array(getfield(c_data, f), Int(d_sizes[f][1]), Int(d_sizes[f][2]))
      push!(dargs, raw)
   end
   return jlData(pd, dargs...)
end

function mapmujoco(pm::Ptr{mjModel}, pd::Ptr{mjData}) 
   c_model = unsafe_load(pm)
   return mapmodel(c_model, pm), mapdata(c_model, pd)
end

# struct manipulation and access
structinfo(T) = Dict(fieldname(T,i)=>(fieldoffset(T,i), fieldtype(T,i)) for i = 1:fieldcount(T))
const minfo = structinfo(mjModel)
const dinfo = structinfo(mjData)

const mjstructs = Dict(mjContact     => structinfo(mjContact),
                       mjWarningStat => structinfo(mjWarningStat),
                       mjTimerStat   => structinfo(mjTimerStat),
                       mjSolverStat  => structinfo(mjSolverStat),

                       mjrContext    => structinfo(mjrContext),

                       mjVFS         => structinfo(mjVFS),
                       mjOption      => structinfo(mjOption),
                       #_global       => structinfo(_global),
                       #quality       => structinfo(quality),
                       #headlight     => structinfo(headlight),
                       #map           => structinfo(map),
                       #scale         => structinfo(scale),
                       #rgba          => structinfo(rgba),
                       mjVisual      => structinfo(mjVisual),
                       mjStatistic   => structinfo(mjStatistic),
                       mjModel       => structinfo(mjModel),

                       mjvPerturb    => structinfo(mjvPerturb),
                       mjvCamera     => structinfo(mjvCamera),
                       mjvGLCamera   => structinfo(mjvGLCamera),
                       mjvGeom       => structinfo(mjvGeom),
                       mjvLight      => structinfo(mjvLight),
                       mjvOption     => structinfo(mjvOption),
                       mjvScene      => structinfo(mjvScene),
                       mjvFigure     => structinfo(mjvFigure))

# access mujoco struct fields through the julia version of model and data
function get(m::jlModel, field::Symbol)
   f_off, f_type = minfo[field]
   pntr = Ptr{f_type}(m.m)
   return unsafe_load(pntr+f_off)
end
function get(m::jlModel, fstruct::Symbol, field::Symbol)
   s_off, s_type = minfo[fstruct]
   @assert s_type in (mjOption, mjVisual, mjStatistic)

   #f_off, f_type = structinfo(s_type)[field]
   f_off, f_type = mjstructs[s_type][field]
   pntr = Ptr{f_type}(m.m)
   return unsafe_load(pntr+s_off+f_off, 1)
end
function get(d::jlData, field::Symbol)
   f_off, f_type = dinfo[field]
   pntr = Ptr{f_type}(d.d)
   return unsafe_load(pntr+f_off, 1)
end
function get(p::Ptr{T}, field::Symbol) where T
   f_off, f_type = mjstructs[T][field]
   pntr = Ptr{f_type}(p)
   return unsafe_load(pntr+f_off, 1)
end
function get(p::Ptr{T}, field::Symbol, i::Int) where T
   f_off, f_type = mjstructs[T][field]
   ET = eltype(f_type)
   @assert f_type <: SVector
   pntr = Ptr{ET}(p)
   unsafe_load(pntr+f_off, i)
end
function get(p::Ptr{T}, field::Symbol, i::Int, j::Int) where T # does row-col conversion
   f_off, f_type = mjstructs[T][field]
   ET = eltype(eltype(f_type))
   @assert f_type <: SVector && eltype(f_type) <: SVector
   #r, c = size(f_type)
   c = sizeof(eltype(f_type))[1]
   #@assert i <= r && i >= 1
   #@assert j <= c && i >= 1
   #idx = (i-1)*c + (j-1)*sizeof(ET)
   idx = (j-1)*sizeof(ET)
   pntr = Ptr{ET}(p)
   unsafe_load(pntr+f_off + (i-1)*c + (j-1)*sizeof(ET), 1)
end


function update_ptr(p::Ptr, offset::Integer, val::Integer)
   unsafe_store!(convert(Ptr{Cint}, (p + offset)), convert(Cint, val))
end
function update_ptr(p::Ptr, offset::Integer, val::mjtNum)
   unsafe_store!(convert(Ptr{mjtNum}, (p + offset)), val)
end
function update_ptr(p::Ptr, offset::Integer, val::SVector)
   #T = eltype(SVector)
   T = typeof(val[1])
   for i=1:length(val)
      unsafe_store!(convert(Ptr{T}, p+offset+(i-1)*sizeof(T)),
                    val[i])
   end
end

# mutate mujoco struct fields through the julia version of model and data
function set(d::jlData, field::Symbol, val::Union{Integer, mjtNum})
   f_off, f_type = dinfo[field]
   update_ptr(d.d, f_off, convert(f_type, val)) 
end
function set(m::jlModel, field::Symbol, val::Union{Integer, mjtNum})
   f_off, f_type = minfo[field]
   update_ptr(m.m, f_off, convert(f_type, val)) 
end
function set(p::Ptr{T}, field::Symbol, val::Union{Integer, mjtNum, SVector}) where T
   f_off, f_type = mjstructs[T][field]
   update_ptr(p, f_off, convert(f_type, val)) 
end
function set(p::Ptr{T}, field::Symbol, val, i::Int) where T # write to element in SVector
   f_off, f_type = mjstructs[T][field]
   ET = eltype(f_type)
   @assert f_type <: SVector
   #@assert typeof(val) == ET
   v = convert(ET, val) # use this as a check
   @assert i <= length(f_type) && i >= 1
   unsafe_store!(convert(Ptr{ET}, (p+f_off+(i-1)*sizeof(ET))), v)
end
function set(p::Ptr{T}, field::Symbol, val, i::Int, j::Int) where T # write to element in SVector
   f_off, f_type = mjstructs[T][field]
   @assert f_type <: SVector && eltype(f_type) <: SVector
   ET = eltype(eltype(f_type))
   v = convert(ET, val) # use this as a check
   #r = size(f_type)[1]
   c = sizeof(eltype(f_type))[1]
   #@assert i <= r && i >= 1
   #@assert j <= c && i >= 1
   #idx = (i-1) + (j-1)*r
   idx = p+f_off + (i-1)*c + (j-1)*sizeof(ET)
   unsafe_store!(convert(Ptr{ET}, idx), v)
end

# set struct within model struct 
function set(m::jlModel, fstruct::Symbol, field::Symbol, val::Union{Integer, mjtNum, SVector})
   s_off, s_type = minfo[fstruct]
   @assert s_type in (mjOption, mjVisual, mjStatistic)

   f_off, f_type = mjstructs[s_type][field]
   update_ptr(m.m, s_off+f_off, convert(f_type, val))
end
function set(p::Ptr{T}, fstruct::Symbol, field::Symbol, val::Union{Integer, mjtNum}) where T
   s_off, s_type = mjstructs[T][fstruct]
   f_off, f_type = mjstructs[s_type][field]
   update_ptr(p, f_off, convert(f_type, val)) 
end

#################################### Name Wrappers

function name2idx(m::jlModel, num::Integer, names::Vector{Cint})
   sname = String(copy(m.names))
   idx = names[1] + 1
   split_names = split(sname[idx:end], '\0', limit=(num+1))[1:num]
   d = Dict{Symbol, Integer}(Symbol(split_names[i]) => i for i=1:num)
   return d
end

function name2range(m::jlModel, names::Vector{Cint}, addresses::Vector{Cint})
   return name2range(m, names, addresses, ones(Cint, length(addresses)))
end

function name2range(m::jlModel, num::Integer,
                    names::Vector{Cint}, addresses::Vector{Cint}, dims::Vector{Cint})
   sname = String(copy(m.names))
   idx = names[1] + 1
   split_names = split(sname[idx:end], '\0', limit=(num+1))[1:num]
   d = Dict{Symbol, AbstractRange}(Symbol(split_names[i]) => (addresses[i]+1):(addresses[i]+dims[i]) for i=1:num)
   return d
end


