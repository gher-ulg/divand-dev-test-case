module WorldOceanDatabase

using NCDatasets
import Requests
using AbstractTrees
import Gumbo
import Glob
import DataArrays

"""
extracttar(tarname,dirname)

`tarname` is a tar.gz file to be extract to `dirname`. 
"""

function extracttar(tarname,dirname)
    if is_windows()
        const exe7z = joinpath(JULIA_HOME, "7z.exe")
        run(pipeline(`$exe7z x $tarname -y -so`, `$exe7z x -si -y -ttar -o$dirname`))
    else
        run(`tar xzf $(tarname) --directory=$(dirname)`)
    end
end

"""
Extract a list for tar archives (one per probe/platform) from the World Ocean Database and places them in `basedir`, e.g. basedir/CTD, basedir/XBT, ...
"""
function extract(tarnames,basedir)
    dirnames = Vector{String}(length(tarnames))
    
    for i = 1:length(tarnames)
        probe = split(tarnames[i],".")[3]
        dirnames[i] = joinpath(basedir,probe)
        @show dirnames[i]
        mkpath(dirnames[i])
        extracttar(tarnames[i], dirnames[i])
    end

    indexnames = [joinpath(dirnames[i],replace(basename(tarnames[i]),".tar.gz",".nc")) for i = 1:length(tarnames)]

    return dirnames,indexnames
end    

""" 
savereq(r,fname)
Save the body request `r` to the file `fname` for debugging.
"""

function savereq(r,fname)
    f = open(fname,"w")
    write(f,readstring(r))
    close(f)
end


"""
dirnames,indexnames = download(lonrange,latrange,timerange,
    variable,email,basedir)

Download data using the NODC web-service. The range parameters are vectors
from with the frist element is the lower bound and the last element is the upper
bound. 



| Variables								| Unit    |
|:--------------------------------------|:--------|
| Temperature							| °C      |
| Salinity								| unitless|
| Oxygen								| ml l⁻¹  |
| Phosphate								| µM      |
| Silicate								| µM      |
| Nitrate and Nitrate+Nitrite			| µM      |
| pH									| unitless|
| Chlorophyll							| µg l⁻¹  |
| Plankton								| multiple|
| Alkalinity							| meq l⁻¹ |
| Partial Pressure of Carbon Dioxide	| µatm    |
| Dissolved Inorganic Carbon			| mM      |
| Transmissivity						| m⁻¹     |
| Pressure								| dbar    |
| Air temperature						| °C      |
| CO2 warming							| °C      |
| CO2 atmosphere						| ppm     |
| Air pressure							| mbar    |
| Tritium								| TU      |
| Helium								| nM      |
| Delta Helium-3						| %       |
| Delta Carbon-14						| ᵒ/ᵒᵒ    |
| Delta Carbon-13						| ᵒ/ᵒᵒ    |
| Argon									| nM      |
| Neon									| nM      |
| Chlorofluorocarbon 11 (CFC 11)		| pM      |
| Chlorofluorocarbon 12 (CFC 12)		| pM      |
| Chlorofluorocarbon 113 (CFC 113)		| pM      |
| Delta Oxygen-18						| ᵒ/ᵒᵒ    |


The parameters of the functions will 
be transmitted to nodc.noaa.gov (http://www.noaa.gov/privacy.html).

* No XBT corrections is applied *
"""

function download(lonrange,latrange,timerange,varname,email,basedir)

    west,east = lonrange[[1,end]]
    south,north = latrange[[1,end]]
    datestart,dateend = timerange[[1,end]]
    URL = "https://www.nodc.noaa.gov/cgi-bin/OC5/SELECT/dbsearch.pl"
    URLextract = "https://www.nodc.noaa.gov/cgi-bin/OC5/SELECT/dbextract.pl"
    URLselect = "https://data.nodc.noaa.gov/woa/WOD/SELECT/"

    # names from the WOD web portal
    variables = Dict(
        "Temperature"							=>	"tem",		# °C                              
        "Salinity"								=>	"sal",		# unitless                        
        "Oxygen"								=>	"oxy",		# ml l⁻¹               
        "Phosphate"								=>	"phos",		# µM                              
        "Silicate"								=>	"sil",		# µM                              
        "Nitrate and Nitrate+Nitrite"			=>	"nit",		# µM                              
        "pH"									=>	"ph",		# unitless                        
        "Chlorophyll"							=>	"chl",		# µg l⁻¹               
        "Plankton"								=>	"bio",		# multiple                        
        "Alkalinity"							=>	"alk",		# meq l⁻¹              
        "Partial Pressure of Carbon Dioxide"	=>	"pco",		# µatm                            
        "Dissolved Inorganic Carbon"			=>	"tco",		# mM                              
        "Transmissivity"						=>	"bac",		# m⁻¹                  
        "Pressure"								=>	"pres",		# dbar                            
        "Air temperature"						=>	"ato",		# °C                              
        "CO2 warming"							=>	"wco",		# °C                              
        "CO2 atmosphere"						=>	"aco",		# ppm                             
        "Air pressure"							=>	"airp",		# mbar                            
        "Tritium"								=>	"tri",		# TU                              
        "Helium"								=>	"he",		# nM                              
        "Delta Helium-3"						=>	"dhe",		# %                               
        "Delta Carbon-14"						=>	"dc14",		# <sup>o</sup>/<sub>oo</sub>      
        "Delta Carbon-13"						=>	"dc13",		# <sup>o</sup>/<sub>oo</sub>      
        "Argon"									=>	"ar",		# nM                              
        "Neon"									=>	"ne",		# nM                              
        "Chlorofluorocarbon 11 (CFC 11)"		=>	"cf11",		# pM                              
        "Chlorofluorocarbon 12 (CFC 12)"		=>	"cf12",		# pM                              
        "Chlorofluorocarbon 113 (CFC 113)"		=>	"cf113",	# pM                              
        "Delta Oxygen-18"						=>	"doxy",		# <sup>o</sup>/<sub>              
    )
    
    variable = variables[varname]
    # ## XBT corrections

    # | value | correction                                        |
    # |-------|---------------------------------------------------|
    # | 0     | No corrections                                    |
    # | 1     | Hanawa et al., 1994 applied (XBT)                 |
    # | 5     | Levitus et al., 2009 applied (XBT/MBT)            |
    # | 6     | Wijffels et al., 2008 Table 1 applied (XBT)       |
    # | 7     | Wijffels et al., 2008 Table 2 applied (XBT)       |
    # | 8     | Ishii and Kimoto, 2009 applied (XBT/MBT)          |
    # | 9     | Gouretski and Reseghetti, 2010 applied (XBT/MBT)  |
    # | 10    | Good, 2011 applied (XBT)                          |
    # | 11    | Hamon et al., 2012 applied (XBT/MBT)              |
    # | 12    | Gourestki, 2012 applied (XBT)                     |
    # | 13    | Cowley et al. 2013 applied (XBT)                  |
    # | 14    | Cheng from Cowley et al. 2013 applied (XBT)       |
    # | 15    | Cheng et al. (2014)                               |

    # unused when requesting NetCDF files!
    xbt_correction = 0
    
    #file_name = "ocldb1504104170.6387"
    #probe_name = "OSD,CTD,XBT,MBT,PFL,DRB,MRB,APB,UOR,SUR,GLD"
    
    r = Requests.post(URL; data = Dict("north" => north, "west" => west, "east" => east, "south" =>  south,
                              "yearstart" => Dates.year(datestart), "monthstart" => Dates.month(datestart), "daystart" => Dates.day(datestart),
                              "yearend" => Dates.year(dateend), "monthend" => Dates.month(dateend), "dayend" => Dates.day(dateend),
                              "variable_all" => "all", "variable_show" => variable,
                              "go" => "   Get an Inventory    ",
                              "criteria_number" => "geosearch,datesearch,varisearch"))
    #curl 'https://www.nodc.noaa.gov/cgi-bin/OC5/SELECT/dbsearch.pl' -H 'Host: www.nodc.noaa.gov' -H 'User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:55.0) Gecko/20100101 Firefox/55.0' -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' -H 'Accept-Language: de,en-US;q=0.7,en;q=0.3' --compressed -H 'Content-Type: application/x-www-form-urlencoded' -H 'Referer: https://www.nodc.noaa.gov/cgi-bin/OC5/SELECT/builder.pl' -H 'DNT: 1' -H 'Connection: keep-alive' -H 'Upgrade-Insecure-Requests: 1' --data "north=$north&west=0&east=$east&south=$south&yearstart=$yearstart&monthstart=1&daystart=1&yearend=$yearend&monthend=1&dayend=1&variable_all=all&variable_show=$tem&go=+++Get+an+Inventory++++&criteria_number=geosearch%2Cdatesearch%2Cvarisearch" > out2.html
    savereq(r,"out2.html")

    doc = Gumbo.parsehtml(readstring(r))
    
    data = Dict{String,String}("what" => "DOWNLOAD DATA")
    
    
    
    for elem in PreOrderDFS(doc.root); 
        if isa(elem,Gumbo.HTMLElement); 
            if Gumbo.tag(elem) == :input 
                
                a = Gumbo.attrs(elem); 
                if "name" in keys(a)
                    
                    if a["name"]  in ["file_name","probe_name","query_results"]
                        data[a["name"]] = a["value"]
                        @show a["name"],a["value"]
                    end
                    
                end
            end; 
        end; 
    end

    file_name = data["file_name"]
    probe_name = data["probe_name"]


    # confirm
    #<form action="/cgi-bin/OC5/SELECT/dbextract.pl" method="post">
    #...
    #<input type="submit" name="what" value="DOWNLOAD DATA" />
    #<input type="hidden" name="file_name" value="ocldb1503990786.2546" />
    #<input type="hidden" name="probe_name" value="OSD,CTD,XBT,MBT,PFL,DRB,MRB,APB,UOR,SUR,GLD" />
    #<input type="hidden" name="query_results" value=":2000:2001:1:1:1:1:0:10.0000:50.0000:30.0000:OSD,CTD,XBT,MBT,PFL,DRB,MRB,APB,UOR,SUR,GLD:::tem::::::::::" />

    #filename=$(grep 'input type="hidden" name="file_name"' out2.html | awk -F\" '{ print $6 }')
    

    r = Requests.post(URLextract; data = data)
    #curl 'https://www.nodc.noaa.gov/cgi-bin/OC5/SELECT/dbextract.pl' -H 'Host: www.nodc.noaa.gov' -H 'User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:55.0) Gecko/20100101 Firefox/55.0' -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' -H 'Accept-Language: de,en-US;q=0.7,en;q=0.3' --compressed -H 'Content-Type: application/x-www-form-urlencoded' -H 'Referer: https://www.nodc.noaa.gov/cgi-bin/OC5/SELECT/dbsearch.pl' -H 'DNT: 1' -H 'Connection: keep-alive' -H 'Upgrade-Insecure-Requests: 1' --data "what=DOWNLOAD+DATA&file_name=$filename&probe_name=OSD%2CCTD%2CXBT%2CMBT%2CPFL%2CDRB%2CMRB%2CAPB%2CUOR%2CSUR%2CGLD&query_results=%3A$yearstart%3A$yearend%3A1%3A1%3A1%3A1%3A$west%3A$east%3A$north%3A$south%3AOSD%2CCTD%2CXBT%2CMBT%2CPFL%2CDRB%2CMRB%2CAPB%2CUOR%2CSUR%2CGLD%3A%3A%3A$tem%3A%3A%3A%3A%3A%3A%3A%3A%3A%3A" > out3.html
    savereq(r,"out3.html")


    ## choose format and correction
    # here 15: Chen 2014


    r = Requests.post(URLextract; data = Dict("format" => "net", "probe_storage" => "none", "csv_choice" => "csv", "level" => "observed", "xbt_corr" => xbt_correction, "email" => email, "what" => "EXTRACT DATA", "file_name" => file_name, "probe_name" => probe_name))
    savereq(r,"out4.html")

    #curl 'https://www.nodc.noaa.gov/cgi-bin/OC5/SELECT/dbextract.pl' -H 'Host: www.nodc.noaa.gov' -H 'User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:55.0) Gecko/20100101 Firefox/55.0' -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' -H 'Accept-Language: de,en-US;q=0.7,en;q=0.3' --compressed -H 'Content-Type: application/x-www-form-urlencoded' -H 'Referer: https://www.nodc.noaa.gov/cgi-bin/OC5/SELECT/dbextract.pl' -H 'DNT: 1' -H 'Connection: keep-alive' -H 'Upgrade-Insecure-Requests: 1' --data "format=net&probe_storage=none&csv_choice=csv&level=observed&xbt_corr=15&email=barth.alexander%40gmail.com&what=EXTRACT+DATA&file_name=$filename&probe_name=OSD%2CCTD%2CXBT%2CMBT%2CPFL%2CDRB%2CMRB%2CAPB%2CUOR%2CSUR%2CGLD" > out4.html

    # number of files available
    probes = split(probe_name,',')
    @show probes
    probes_available = String[]

    waittime = 0 # time to wait in cycles

    for i = 1:1000
        for probe in probes
            if !(probe in probes_available)
                dataurl = "$(URLselect)/$(file_name).$(probe).tar.gz"

                # check if dataurl exists already
                if Requests.head(dataurl).status == 200
                    println("$(probe) is now available")
                    push!(probes_available,probe)

                    waittime = i
                #else
                    #@show "no",probe
                end
            end
        end

        #@show waittime
        # wait maximum 2 additional cycles after a file have become available
        if (waittime != 0) & (i == waittime + 2)
            #@show i,waittime
            break
        end

        sleep(10)
    end

    # make sure that file are complet
    sleep(2)

    mkpath(basedir)
    tarnames = String[]


    for probe in probes_available
        dataurl = "$(URLselect)/$(file_name).$(probe).tar.gz"
        push!(tarnames,joinpath(basedir,"$(file_name).$(probe).tar.gz"))

        for ntries = 1:3
            try
                Base.download(dataurl,tarnames[end])
                # download was successful
                break
            catch e
                if ntries != 3
                    rethrow(e)
                end
            end
        end
    end


    dirnames,indexnames = extract(tarnames,basedir)
    return dirnames,indexnames
end

"""
load(T,dirname,indexname,varname)

Load all profiles with the NetCDF variable `varname` in `dirname` indexed with 
the NetCDF file `indexname`.
T is the type (e.g. Float64) for numeric return values.
"""

function load(T,dirname::AbstractString,indexname,varname)
    profiles = T[]
    zs = T[]
    lons = T[]
    lats = T[]
    times = DateTime[]
    ids = String[]

    load!(dirname,indexname,varname,profiles,lons,lats,zs,times,ids)
    return profiles,lons,lats,zs,times,ids
end

"""
append to profiles,lons,lats,zs,times,ids
"""
function load!(dirname,indexname,varname,profiles,lons,lats,zs,times,ids)
    indexnc = NCDatasets.Dataset(indexname)

    cast = indexnc["cast"][:].data :: Vector{Int32}

    # WORLD OCEAN DATABASE 2013 USER’S MANUAL
    # page 39, doi:10.7289/V5DF6P53
    const accepted = 0


    for i = 1:length(cast)
        id = @sprintf("wod_%09dO",cast[i])
        wodname = joinpath(dirname,@sprintf("wod_%09dO.nc",cast[i]))

        if !isfile(wodname)
            warn("File $(wodname) does not exist")
            continue
        end

        NCDatasets.Dataset(wodname) do nc
            #@show wodname, varname in nc
            if varname in nc

                profile = nc[varname][:]
                z = nc["z"][:]
                lon = nc["lon"][:]
                lat = nc["lat"][:]
                time = nc["time"][:]

                profileflag = nc["$(varname)_WODflag"][:]
                sigfigs = nc["$(varname)_sigfigs"][:].data
                # some date are flagged as accepted but have *_sigfigs equal
                # to zero and bogus value

                good = ((profileflag .== accepted)  .&
                        (.!DataArrays.ismissing.(profile)) .&
                        (.!DataArrays.ismissing.(z)) .&
                        (sigfigs .> 0))
                
                sizegood = (sum(good),)
                
                append!(profiles,profile[good].data)
                append!(zs,z[good].data)
                append!(lons,fill(lon,sizegood))
                append!(lats,fill(lat,sizegood))
                append!(times,fill(time,sizegood))
                append!(ids,fill(id,sizegood))

                #@show length(profiles),length(zs)
                
            end
        end

    end

    close(indexnc)
end


"""
Load a list  of directories `dirnames`.
"""
function load(T,dirnames::Vector{<:AbstractString},indexnames,varname)
    profiles = T[]
    zs = T[]
    lons = T[]
    lats = T[]
    times = DateTime[]
    ids = String[]
    
    for i = 1:length(dirnames)
        load!(dirnames[i],indexnames[i],varname,profiles,lons,lats,zs,times,ids)
    end

    return profiles,lons,lats,zs,times,ids
end


"""
Load a list profiles under the directory `basedir` assuming `basedir` was 
populated by `WorldOceanDatabase.download`.
"""
function load(T,basedir::AbstractString,varname)
    # all directories under basedir
    dirnames = filter(isdir,[joinpath(basedir,d) for d in readdir(basedir)])
    # the files starting with ocldb (i.e. matching basedir/*/ocldb*)
    
    indexnames = [joinpath(dirn,sort(filter(d -> startswith(d,"ocldb"),readdir(dirn)))[1]) for dirn in dirnames]
    
    return load(T,dirnames,indexnames,varname)    
end
    

end
