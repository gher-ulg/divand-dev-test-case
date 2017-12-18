using PyPlot
import WorldOceanDatabase
import divand
using DataStructures
using DataArrays

Vocab = divand.Vocab

# resolution
dx = dy = 0.25
dx = dy = 1.

# vectors defining the longitude and latitudes grids
# Here longitude and latitude correspond to the Mediterranean Sea
lonr = -7:dx:37
latr = 30:dy:46

# depth levels
depthr = [0.,10.,20.]

# time range of the in-situ data
timerange = [Date(2016,1,1),Date(2016,12,31)]

# months for the climatology (January, February,...)
timer = [1.,2.,3.]

# Name of the variable
varname = "Temperature"

# Email for downloading the data
email = "a.barth@ulg.ac.be"

# path to save the results (will be created if necessary)
basedir = expanduser("~/Downloads/WOD/Med-2016")

metadata = OrderedDict(
    # Name of the project (SeaDataCloud, SeaDataNet, EMODNET-Chemistry, ...)
    "project" => "SeaDataCloud",

    # URN code for the institution EDMO registry,
    # e.g. SDN:EDMO::1579
    "institution_urn" => "SDN:EDMO::1579",

    # Production group
    "production" => "Diva group. E-mails: a.barth@ulg.ac.be, swatelet@ulg.ac.be",

    # Name and emails from authors
    "Author_e-mail" => ["Your Name1 <name1@example.com>", "Other Name <name2@example.com>"],

    # Source of the observation
    "source" => "observational data from SeaDataNet/EMODNet Chemistry Data Network",

    # Additional comment
    "comment" => "...",

    # SeaDataNet Vocabulary P35 URN
    # http://seadatanet.maris2.nl/v_bodc_vocab_v2/search.asp?lib=p35
    # example: SDN:P35::WATERTEMP
    "parameter_keyword_urn" => "SDN:P35::WATERTEMP",

    # List of SeaDataNet Parameter Discovery Vocabulary P02 URNs
    # http://seadatanet.maris2.nl/v_bodc_vocab_v2/search.asp?lib=p02
    # example: ["SDN:P02::TEMP"]
    "search_keywords_urn" => ["SDN:P02::TEMP"],

    # List of SeaDataNet Vocabulary C19 area URNs
    # SeaVoX salt and fresh water body gazetteer (C19)
    # http://seadatanet.maris2.nl/v_bodc_vocab_v2/search.asp?lib=C19
    # example: ["SDN:C19::3_1"]
    "area_keywords_urn" => ["SDN:C19::3_1"],

    "product_version" => "1.0",

    # NetCDF CF standard name
    # http://cfconventions.org/Data/cf-standard-names/current/build/cf-standard-name-table.html
    # example "standard_name" = "sea_water_temperature",
    "netcdf_standard_name" => "sea_water_temperature",

    "netcdf_long_name" => "sea water temperature",

    "netcdf_units" => "degree Celsius",

    # Abstract for the product
    "abstract" => "...",

    # This option provides a place to acknowledge various types of support for the
    # project that produced the data
    "acknowledgment" => "...",

    # Digital Object Identifier of the data product
    "doi" => "...")




doplot = true
doplot = false

# bathymetry
# See instructions at https://github.com/gher-ulg/divand.jl/#example-data
bathname = joinpath(dirname(@__FILE__),"..","..","divand-example-data","Global","Bathymetry","gebco_30sec_16.nc")

# bathymetry is a global data set
isglobal = true

# error variance of the observations (normalized by the error variance of the background field)
epsilon2 = 0.1

# size of the domain
sz = (length(lonr),length(latr),length(depthr),length(timer))

# horizontal correlation length in meters
lenx = fill(300_000.,sz) # m
leny = fill(300_000.,sz) # m


# vertical correlation length in meters
# correlation increases at depth
lenz = Array{Float64}(sz)
for n = 1:sz[4]
    for k = 1:sz[3]
        for j = 1:sz[2]
            for i = 1:sz[1]
                lenz[i,j,k,n] = 10 + depthr[k]/5
            end
        end
    end
end

# correlation time-scale in month
lent = fill(1.,sz) # month



### end of user input

# World Ocean Database: example for bulk access data by simulating a web-user
# SeaDataNet will provide a dedicated machine-to-machine interface during
# the SeaDataCloud project

#WorldOceanDatabase.download(lonr,latr,timerange,varname,email,basedir)




# download all data under basedir as a double-precision floating point variable
val,lon,lat,depth,time,ids = WorldOceanDatabase.load(Float64,basedir,varname)

# additional sub-setting and discard bogus negative temperatures
sel = ((val .> 0 )
       .& (minimum(depthr) .<= depth .<= maximum(depthr))
       .& (minimum(timer) .<= Dates.month.(time) .<= maximum(timer)))

val = val[sel]
lon = lon[sel]
lat = lat[sel]
depth = depth[sel]
time = time[sel]
ids = ids[sel]

# contour for plots
cxi,cyi,mask0 = divand.load_mask(bathname,isglobal,minimum(lonr),maximum(lonr),1/60,minimum(latr),maximum(latr),1/60,0)

# plot observations
if doplot
    figure()
    plotmonth = 1
    plotdepth = 10

    title("Temperature observations (month $(plotmonth), around depth $(plotdepth) m)")
    # around means here +/-5 meters
    selection = (abs.(depth - plotdepth) .<= 5) .& (Dates.month.(time) .== plotmonth);

    contourf(cxi,cyi,mask0',levels  = [0.,0.5],colors = [[.5,.5,.5]])
    scatter(lon[selection],lat[selection],20,val[selection],cmap = "jet")
    colorbar(orientation="horizontal")

    # sets the correct aspect ratio
    gca()[:set_aspect](1/cos(mean(latr) * pi/180))
end


# define the geo-temporal domain
# mask indicates wether a grid point is land or sea (based on the bathymetry)
# pm,pn,po,pp: correspond to the resolution of grid in space and time
# xi,yi,zi,ti: the location of the grid cells as 4D-arrays
mask,(pm,pn,po,pp),(xi,yi,zi,ti) = divand.domain(bathname,isglobal,lonr,latr,depthr,timer)

# size of the domain
@show size(mask)

# convert time to month
time2 = Dates.month.(time)

# average over longitude and latitude for the background estimate
toaverage = [true,true,false,false]

# compute the background and the anomalies
@time fmb,vaa = divand.divand_averaged_bg(mask,(pm,pn,po,pp),(xi,yi,zi,ti),(lon,lat,depth,time2),val,(lenx,leny,4*lenz,4*lent),epsilon2*10,toaverage)

# perform the analysis
@time fi,erri = divand.divandgo(mask,(pm,pn,po,pp),(xi,yi,zi,ti),(lon,lat,depth,time2),vaa,(lenx,leny,lenz,lent),epsilon2)

#tol = 1e-3
#@time fi2,s2=divand.varanalysis(mask,(pm,pn,po,pp),(xi,yi,zi,ti),(lon,lat,depth,time2),vaa,(lenx,leny,lenz,lent),epsilon2; progress = divand.cgprogress, tol = tol);

# add the background
fanalysis = fi + fmb

# verify the range (excluding land points)
@show extrema(fanalysis[mask])

if doplot
    figure()
    # plot the first depth level and the first time instance
    k = 1
    n = 1
    title("Temperature analysis (month $(timer[n]), depth $(depthr[k]) m)")
    contourf(xi[:,:,k,n],yi[:,:,k,n],fanalysis[:,:,k,n],100,cmap="jet")
    colorbar(orientation="horizontal")

    # plot land
    contourf(cxi,cyi,mask0',levels  = [0.,0.5],colors = [[.5,.5,.5]])

    # plot observation location
    selection = (abs.(depth - depthr[k]) .<= 5) .& (Dates.month.(time) .== timer[n]);
    plot(lon[selection],lat[selection],"k.",ms=2)

    # sets the correct aspect ratio
    gca()[:set_aspect](1/cos(mean(latr) * pi/180))
end

# save the results in a NetCDF
divand.divand_save("temperature.nc",mask,"temperature",fanalysis)


filename = "temperature2.nc"
varname = "temperature"

ncglobalattrib,ncvarattrib = divand.SDNMetadata(metadata,filename,varname,lonr,latr,fanalysis)

climatology_bounds = Array{DateTime}(length(timer),2)

climatology_bounds[:,1] = DateTime(Dates.year(timerange[1]),1,1) + Dates.Month.(0:length(timer)-1)
climatology_bounds[:,2] = DateTime(Dates.year(timerange[end]),1,1) + Dates.Month.(1:length(timer))


#climatology_bounds[:,1] = timerange[end] + Dates.Month.([-2,-1,0])


divand.divand_save2(filename,mask,(lonr,latr,depthr,timer),
                    fanalysis,varname;
                    ncglobalattrib = ncglobalattrib,
                    relerr = erri,
                    climatology_bounds = climatology_bounds,
                    ncvarattrib = ncvarattrib
                    )
