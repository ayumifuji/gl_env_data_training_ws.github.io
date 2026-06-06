%% Hands-on Session 2: Comparison of the lake model outputs with observations
% In this hands-on session, we will compare Lake Erie Operational Forecast 
% System (LEOFS) model output with buoy observations and, optionally, 
% satellite-derived lake surface temperature from GLSEA.
%
% In the Hands-on Session 1, we worked with a single model output file. 
% Here, we extend that workflow to a short time series by downloading multiple 
% hourly model files. By the end of the guided portion, you will be able to:
%
% (1) Download multiple hourly GLOFS/LEOFS NetCDF files from NOAA’s public archive
% (2) Download and read buoy observations from the National Data Buoy Center
% (3) Find the model grid node closest to a buoy location
% (4) Extract a model lake surface temperature time series
% (5) Plot and interpret model–observation differences
%
% Also see HandOnSession1.m for a basic workflow to download, read, 
% and visualize a LEOFS output file.
% Estimated Time: 1.5 hour for core demonstration
%
%
% Created 5/25/2026
% Written by David Cannon (djcannon@umich.edu)
clear; close all; clc;

%% Part 0: Set Parameters For Demonstration
save_dir='C:\Users\cannon\Desktop\DataWorkshopCodes'; %%%%% SET THIS DIRECTORY FOR YOURSELF
start_date=datetime(2025,6,1); %%%%%% Set the start date for time series
end_date=datetime(2025,6,7); %%%%%% Set the end date for time series

%%%%%%%%%%%%% GLOFS PARAMETERS
systemname = 'leofs';%Erie: leofs; Michigan-Huron: lmhofs; Superior: lsofs; Ontario: loofs

%%%%%%%%%%%%% BUOY PARAMETERS
% this example uses buoy 45005 - https://www.ndbc.noaa.gov/station_page.php?station=45005
buoycode=45005;
buoy_lon = -82.398;
buoy_lat = 41.677;

%% Part 1: Set up environment and download multiple LEOFS/GLOFS files
% In the first hands-on session, we focused on a single timeslice. 
% This time, we will look into a timeseries data. GLOFS datastream provides 
% one time slice per file. Therefore, if you'd like to look into temporal 
% changes, you will have to download multiple files.
%%%%%%%%%%%%%% 1.1 Setup directories to save files
save_dirg=[save_dir,'\glofs'];
disp(['GLOFS files will be saved in: ',save_dirg]);

%%%%%%%%%%%%%% 1.2 Download 7-day long GLOFS outputs
% In this example, we are downloading data from June 1-7, 2025. You are 
% welcome to explore another period. The process involves downloading hourly 
% files (a total of 168 files) and takes a few minutes to complete.
%
% Note: Download times may vary depending on network speed and other factors. 
% If downloads take longer than expected, participants can reduce the date 
% range to 2–3 days.
%
% In this notebook, GLOFS refers to NOAA’s Great Lakes Operational Forecast 
% System family. LEOFS is the Lake Erie member of that system, and it is the 
% example system used here. This example downloads data for Lake Erie (leofs). 
% If you'd like, you can also specify a system for another Great Lake.
% LEOFS: Lake Erie Operational Forecast System
% LMHOFS: Lake Michigan-Huron Operational Forecast System
% LSOFS: Lake Superior Operational Forecast System
% LOOFS: Lake Ontario Operational Forecast System

%%%%%%%%%%%% Configure Model Download Parameters
bucket = 'noaa-nos-ofs-pds';

%%%%%%%%%%%% Make a new directory if needed
if ~exist(save_dirg, 'dir')
    mkdir(save_dirg);
end

%%%%%%%%%%% Loop through days and download files
datei=start_date:days(1):end_date;
nn=1;%start a counter for file names.
for xx=1:length(datei)
    current_date=datei(xx);
    yearstr = sprintf('%04d', year(current_date));
    monstr = sprintf('%02d', month(current_date));
    daystr = sprintf('%02d', day(current_date));
    for cycle=0:6:18
        for houri=0:5
            cyclestr=sprintf('%02d', cycle);
            hourstr=sprintf('%03d', houri);
            filename = sprintf('%s.t%sz.%s%s%s.fields.n%s.nc', systemname, cyclestr,yearstr, monstr, daystr,hourstr);
            save_path = fullfile(save_dirg, filename);
            
            key = sprintf('%s/netcdf/%s/%s/%s/%s', systemname, yearstr, monstr, daystr, filename);
            s3_url=['s3://',bucket,'/',key];

            disp(['Downloading ',key,'...']);
            
            %%%%%%% Add mechanism to retry in case there are network issues
            max_retries=5;
            retries=0;
            if ~isfile(save_path)
                while retries<max_retries
                    try
                        copyfile(s3_url,save_path);
                        retries=max_retries+1;
                        all_files{nn}=filename;
                        nn=nn+1;
                    catch
                        retries=retries+1;
                        disp(['Connection Error: Retrying (',num2str(retries),'/',num2str(max_retries),')']);
                    end
                end
            else
                disp([filename,'is already in GLOFS directory. Skipping download']);
                all_files{nn}=filename;
                nn=nn+1;
            end
        end
    end
end

%%%%%%%%%%%%%% 1.3 Double check that all files have been downloaded
expected_num_files=length(datei).*24;
disp([num2str(length(all_files)),' files downloaded']);%2 files are "hidden". ie. not downloaded
disp([num2str(expected_num_files),' files expected']);

%% Part 2: Download and Inspect Buoy Observations
% 2.1 Download Western Lake Erie buoy data from the NDBC site
% Next, we will download buoy observation data from the National Data Buoy 
% Center (NDBC). This example uses an offshore buoy in Western Lake Erie, but 
% you are welcome to try another buoy stations.

%%%%%%%%%%%% Set some download parameters
save_dirb=[save_dir,'\buoy'];
buoyyear=year(median([start_date,end_date]));
disp(['Buoy files will be saved in: ',save_dirb]);

%%%%%%%%%%%% Make a new directory if needed
if ~exist(save_dirb, 'dir')
    mkdir(save_dirb);
end

%%%%%%%%%%% download buoy data
filenamee=[num2str(buoycode),'h',num2str(buoyyear),'.txt.gz'];
buoy_url=['https://www.ndbc.noaa.gov/data/historical/stdmet/',filenamee];
websave([save_dirb,'\',filenamee],buoy_url);
gunzip([save_dirb,'\',filenamee],save_dirb);

%% 2.2 Read the Buoy Data
% The buoy data is in the ASCII format (text based, human readable). 
% You can view it using a text editor if you'd like. Here, we will import
% using typical matlab options

% Define Column names (find these by opening the file in a text  editor)
cols = ["YY", "MM", "DD", "hh", "mm", ...
    "WDIR", "WSPD", "GST", "WVHT", "DPD", "APD", "MWD", ...
    "PRES", "ATMP", "WTMP", "DEWP", "VIS", "TIDE"];

% define the file name and path...
txt_filee=[save_dirb,'\',num2str(buoycode),'h',num2str(buoyyear),'.txt'];

% set import options
opts = delimitedTextImportOptions("NumVariables", numel(cols));
opts.Delimiter = " ";
opts.ConsecutiveDelimitersRule = "join";
opts.LeadingDelimitersRule = "ignore";
opts.DataLines = [3 Inf];
opts.VariableNames = cols;
opts.VariableTypes = repmat("double", 1, numel(cols));
opts = setvaropts(opts, cols, "TreatAsMissing", ["99", "999","999.0","99.00","99.0"]);

% import data
df = readtable(txt_filee, opts);

disp("Below is the original table:");
disp(head(df));
disp(" ");

% Add a datetime column
dt = datetime(df.YY, df.MM, df.DD, df.hh, df.mm, zeros(height(df), 1));
df.datetime = dt;
df = removevars(df, ["YY", "MM", "DD", "hh", "mm"]);

% Optional: convert the table to a matlab timetable
df2 = table2timetable(df, "RowTimes", "datetime");

disp("Below is the table presented as a matlab timetable:");
disp(head(df2));

%% 2.3 Make a timeseries plot of buoy lake surface temperatures
% As you can see, there are a number of meteorological variables 
% (WDIR, WSPD, GST....). You can check out what they mean in the NDBC's 
% data description page (https://www.ndbc.noaa.gov/faq/measdes.shtml).
%
% Here, we will be looking at the water surface temperature data (WTMP). 
% Let's begin by making a quick timeseries plot.

figure;
plot(df2.datetime,df2.WTMP);
xlabel('Date');ylabel('Water Temperature (\circC)');

%% Part 3: Find the nearest model node and extract model time series
% In order to compare the lake surface temperature from the model outputs 
% (LEOFS) and the buoy observation, we will first need to extract the LEOFS 
% data at the closest to the buoy location. You can check the coordinate 
% (longitude and latitude) from the NDBC site. In case of 45005, it's 
% 41.677 N 82.398 W (41°40'36" N 82°23'54" W).
%
% We also have to concatenate the series of 7-day (168-hour) long LEOFS 
% data files.

% 3.1 Create a list of all LEOFS data files
% The downloaded LEOFS files are not concatenated in time (one file per 
% time slice). We will first create a list of all LEOFS data files, sorted 
% in time.
%%%%%%%%%% find file names
file_pattern=[systemname,'.t*z.*.fields.n*.nc'];
files = dir([save_dirg,'\',file_pattern]);
file_names={files.name}';

%%%%%%%%%% extract cycle, date, and hour information from names
for xx=1:length(file_names)
    filename=file_names{xx};
    tokens = regexp(filename, ...
        [systemname,'\.t(\d{2})z\.(\d{8})\.fields\.n(\d{3})\.nc'], ...
        "tokens", "once");
    if isempty(tokens)
        yyyymmdd(xx) = "99999999";
        cycle_hour(xx) = 99;
        n_hour(xx) = 999;
    else
        cycle_hour(xx) = str2double(tokens{1});
        yyyymmdd(xx) = string(tokens{2});
        n_hour(xx) = str2double(tokens{3});
    end
end

%%%%%%%%%% Sort file names by date, then cycle, then hour
filenameT=table(yyyymmdd',cycle_hour',n_hour',file_names,'VariableNames',...
    {'yyyymmdd', 'cycle_hour', 'n_hour', 'file'});
sortTable = sortrows(filenameT, {'yyyymmdd', 'cycle_hour', 'n_hour'});
sorted_files=sortTable.file;

disp(['Found ',num2str(length(sorted_files)),' relevant GLOFS files']);

%% Find the nearest node of LEOFS to the buoy location 
% Next, we will find the nearest node of LEOFS mesh to the buoy location. 
% This allows us to extract the data at the specific node only, rather than 
% the whole mesh data, saving significant amount of time for processing.

% define buoy lon & lat
% Again, you can find this on the buoy landing page [https://www.ndbc.noaa.gov/]
target_lon = buoy_lon;
target_lat = buoy_lat;

% Open a single GLOFS file to grab the lat/lon coordinates of each node. 
% This grid does not change between time steps
lon_node=ncread([save_dirg,'/',sorted_files{1}], 'lon');
lon_node= mod(lon_node + 180, 360) - 180;
lat_node=ncread([save_dirg,'/',sorted_files{1}], 'lat');

% Calculate distance between buoy location and all model nodes
dist=distance(target_lat,target_lon,lat_node,lon_node);
dist_km=deg2km(dist);

% Find the index for the nearest node
nearest_node=find(dist_km==min(dist_km),1);
disp(['Nearest node index: ', num2str(nearest_node)]);
disp(['Nearest model lon: ', num2str(lon_node(nearest_node))]);
disp(['Nearest model lat: ', num2str(lat_node(nearest_node))]);

%% 3.3 Extract data from LEOFS
% We will extract data from the LEOFS files (sorted in time as in the 
% 'files' list), just for the surface (siglay=0), and at the nearest node 
% to the buoy location. While this saves a significant amount of time as 
% opposed to reading data over the entire vertical (or sigma) layers and 
% the entire node, it still takes some time to read all the 168 files. 
% Estimated time for this process is 6-7 mins.

top_layer_index=1;%set index of top sigma layer in file
for xx=1:length(sorted_files)
    % define file
    filee=[save_dirg,'\',sorted_files{xx}];
    disp(sorted_files{xx});
    info = ncinfo(filee);
    % find the time reference to convert time units
    timeloc=find(strcmp({info.Variables.Name},'time'));
    timeatt=info.Variables(timeloc).Attributes(2).Value;
    dateref=datetime(timeatt(15:end),'InputFormat','yyyy-MM-dd HH:mm:ss');

    % read variables
    time0 = ncread(filee, 'time');
    timei=dateref+seconds(time0);%%%%% Convert time units based on dateref...
    %grab top layer of temperature only
    tempi=ncread(filee,'temp',[nearest_node,top_layer_index,1],[1,1,Inf]);

    % add date to time series
    timet(xx)=timei;
    tempt(xx)=tempi;
end

% Make a simple figure to check it out!
figure;
plot(timet,tempt);
xlabel('Date');ylabel('Surface Temperature (\circC)');
title([systemname,' [lon: ',num2str(lon_node(nearest_node)),', lat: ',num2str(lat_node(nearest_node)),']']);

%% Part 4: Compare model and buoy lake surface temperature
% Finally, we will plot a timeseries of the lake surface temperature from 
% the LEOFS model outputs, and the buoy observations. The comparison is for 
% the 7-day period for which we downloaded the LEOFS model outputs.

% make the figure
figure;
plot(timet,tempt);hold on;
plot(df2.datetime,df2.WTMP);
xlabel('Date');ylabel('Surface Temperature (\circC)');

% set the x-axis limits to match simulations...
xlim([timet(1) timet(end)]);

% set the y-axis limits to zoom in on data...
ylim([12 19]);

% add legend
legend(systemname,['Buoy ',num2str(buoycode)]);

% You can see the gradual warming of lake surface temperatture, as the time 
% progresses from early to mid summer. You can also see the diurnal 
% (day-night) cycle. Note that the times are in UTC (Coordinated Universal Time).  
%
% Because LEOFS/FVCOM uses an unstructured grid, the nearest model node may 
% not be exactly at the buoy location.
% The comparison is therefore between the buoy and the closest model grid 
% point, not a perfectly colocated measurement.

%% %%%%%%%%%%%% Checkpoint: interpret the comparison
% Take 2–3 minutes to discuss with a neighbor:
%
% 1. Does LEOFS capture the overall warming trend during this period?
% 2. Does LEOFS capture the day–night temperature cycle?
% 3. Is there a consistent warm or cold bias?
% 4. Why might the buoy observations have a “stair-step” appearance?
% 5. What are possible reasons for differences between a model grid point 
%    and a buoy measurement?
%
% You are welcome to explore different visualizations, such as adding more 
% time ticks, using different color schemes, comparing at another buoy 
% location, and calculating differences. Calculating differences is
% especially interesting, since you'll need to interpolate the time steps
% to match. 

%% Optional: Add GLSEA data
% If time allows, we will add GLSEA satellite-derived lake surface 
% temperature to the comparison.
%
% GLSEA provides daily lake surface temperature estimates on a regular 
% latitude–longitude grid. Unlike the buoy, which is a point measurement, 
% GLSEA represents a gridded satellite-based product. This makes it useful 
% for spatial context, but it may differ from buoy observations because of 
% cloud cover, spatial averaging, satellite retrieval assumptions, and timing.
%
%Through this optional analysis, we can evaluate the differences among the 
% three datasets.
%
% First, we will begin by downloading GLSEA data for the 7-day period.

save_dirglsea=[save_dir,'\glsea'];
disp(['GLSEA files will be saved in: ',save_dirglsea]);

%%%%%%%%%%%% Configure Model Download Parameters
url_glsea='https://apps.glerl.noaa.gov/thredds/fileServer/glsea_nc_3';

%%%%%%%%%%%% Make a new directory if needed
if ~exist(save_dirglsea, 'dir')
    mkdir(save_dirglsea);
end

%%%%%%%%%%% Loop through days and download files
datei=start_date:days(1):end_date;
for xx=1:length(datei)
    current_date=datei(xx);
    yearstr = sprintf('%04d', year(current_date));
    monstr = sprintf('%02d', month(current_date));
    daystr = sprintf('%03d', day(current_date,'dayofyear'));
    
    filenamee=[yearstr,'_',daystr,'_glsea_sst.nc'];
    url_download=[url_glsea,'/',yearstr,'/',monstr,'/',filenamee];
    options=weboptions;options.Timeout=15; 

    %%%%%%% Add mechanism to retry in case there are network issues
    max_retries=5;
    retries=0;
    if ~isfile([save_dirglsea,'\',filenamee])
        while retries<max_retries
            try
                websave([save_dirglsea,'\',filenamee],url_download,options);
                retries=max_retries+1;
            catch
                retries=retries+1;
                disp(['Connection Error: Retrying (',num2str(retries),'/',num2str(max_retries),')']);
            end
        end
    else
        disp([filenamee,' is already in GLSEA directory. Skipping download']);
    end
end

%% Combine GLSEA Data File and Find the Closest Point to Buoy
% Similarly to the LEOFS outputs, we will read data at a point closest to 
% the buoy, and append the data in time. If you would like to plot the GLSEA 
% lake surface temperature on a map, please refer to supplemental_GLSEA.m. 
% Because GLSEA is on a regular grid and has longitude (lon) and latitude 
% (lat) as dimensions. Extracting the nearest point is much simpler than 
% that for LEOFS (or FVCOM).

% find all downloaded files...
file_pattern='*glsea_sst.nc';
files = dir([save_dirglsea,'\',file_pattern]);
file_names=sort({files.name})'; % no need for fnacy sorting this time!

% find point closest to buoy...
%%%%%%% define buoy lon & lat [https://www.ndbc.noaa.gov/station_page.php?station=45005]
target_lon = buoy_lon;
target_lat = buoy_lat;

%%%%%%% open a single glsea file to find lat/lon
fileei=[save_dirglsea,'\',file_names{1}];
info=ncinfo(fileei);
lon_glsea=ncread(fileei,'lon');
lat_glsea=ncread(fileei,'lat');

%%%%%%% Find distance between buoy location and each grid point...
lonmat=repmat(lon_glsea,1,length(lat_glsea));
latmat=repmat(lat_glsea',length(lon_glsea),1);
dist=distance(target_lat,target_lon,latmat,lonmat);
dist_km=deg2km(dist);

%%%%%%%% find closest cell to buoy...
[row,col]=find(dist_km==min(dist_km,[],'all'));
station_loc=[row,col];

for xx=1:length(file_names)
    filee=[save_dirglsea,'\',file_names{xx}];
    ssti=ncread(filee,'sst',[station_loc(1) station_loc(2) 1],[1 1 inf]);
    timei=ncread(filee,'time');

    tempt_glsea(xx)=ssti;
    timet_glsea(xx)=timei;
end

% convert date based on time attributes (see info)
date_glsea=datetime(1970,1,1,0,0,0)+seconds(timet_glsea);

% Make a simple figure!
figure;
plot(date_glsea,tempt_glsea);
xlabel('Date');ylabel('Lake Surface Temperature (\circC)');
title(['lon: ',num2str(lonmat(station_loc(1), station_loc(2))),', lat: ',...
    num2str(latmat(station_loc(1), station_loc(2)))]);

%% Now add this line to the last plot we made!
% make the figure
figure;
plot(timet,tempt);hold on;
plot(df2.datetime,df2.WTMP);
plot(date_glsea,tempt_glsea,'ro','MarkerFaceColor','r');
xlabel('Date');ylabel('Surface Temperature (\circC)');

% set the x-axis limits to match simulations...
xlim([timet(1) timet(end)]);

% set the y-axis limits to zoom in on data...
ylim([12 19]);

% add legend
legend(systemname,['Buoy ',num2str(buoycode)],'GLSEA');

%% Final Thoughts
% What do you observe in your comparison? There are a lot of interesting 
% considerations: What difference do you see in GLSEA satellite observation 
% from buoy observation? Which of GLSEA or buoy do you think is useful for 
% verifying the model outputs?
%
% You are welcome to refer to further readings below, and discuss with other 
% participants and your colleagues.
%
% Further readings and data sources
% NOAA National Ocean Service Operational Forecast Systems: https://tidesandcurrents.noaa.gov/models.html
% NOAA National Data Buoy Center: https://www.ndbc.noaa.gov/
% NOAA GLERL Great Lakes Surface Environmental Analysis: https://coastwatch.glerl.noaa.gov/glsea/
% NOAA NOS OFS public data archive on AWS: https://registry.opendata.aws/noaa-ofs/