# version of library to download
const version = v"1.50"

using BinDeps
@BinDeps.setup

function compatible_version(lib, handle)
   major, minor, rev = Ref{Cint}(), Ref{Cint}(), Ref{Cint}()
   f = Libdl.dlsym(handle, :mj_version)
   f == C_NULL && return false
   v = ccall(f, Int32, ())
   return v >= 150
end

#mujoco = library_dependency("libmujoco", aliases=["libmujoco150nogl", "libmujoco150"], validate=compatible_version)
mujoco = library_dependency("libmujoco", aliases=["libmujoco150"], validate=compatible_version)

baseurl = "https://www.roboti.us/download/mjpro150_"
basedir = dirname(@__FILE__)
println("root: $basedir")
unpack = joinpath(basedir, "mjpro150")
libpath = unpack*"/bin"

# library source code
if is_linux()
   push!(BinDeps.defaults, Binaries) # fixes some unknown, build-blocking issue...
   url = baseurl*"linux.zip"
   info("Downloading: ", url, " to ", unpack)
   provides(Binaries, URI(url), mujoco, unpacked_dir=unpack, installed_libpath=libpath)
elseif is_apple()
   push!(BinDeps.defaults, Binaries) # fixes some unknown, build-blocking issue...
   url = baseurl*"osx.zip"
   info("Downloading: ", url, " to ", unpack)
   provides(SimpleBuild,
            (@build_steps begin
                CreateDirectory(joinpath(basedir, "downloads"))
                FileDownloader(string(url),
                               joinpath(basedir, "downloads/mjpro150_osx.zip"))
                FileUnpacker(joinpath(basedir, "downloads/mjpro150_osx.zip"),
                             basedir, "mjpro150")
             end), mujoco, installed_libpath=libpath)
elseif is_windows()
   url = baseurl*"win$(Sys.WORD_SIZE).zip"
   info("Downloading: ", url, " to ", unpack)
   provides(Binaries, URI(url), mujoco, unpacked_dir=unpack, installed_libpath=libpath)
end

@BinDeps.install Dict(:libmujoco=>:libmujoco)

is_linux() && pop!(BinDeps.defaults)

