%% Supplemental GLSEA Analysis
%
% In this supplemental script, we will download, read, and visualize a 
% spatial map of lake surface temperature from the Great Lakes Surface 
% Environmental Analysis (GLSEA).
%
%
% Created 5/25/2026
% Written by David Cannon (djcannon@umich.edu)
clear; close all; clc;
%% Part 0: Set Parameters For Demonstration
save_dir='C:\Users\cannon\Desktop\DataWorkshopCodes'; %%%%% SET THIS DIRECTORY FOR YOURSELF
date_of_interest=datetime(2025,6,1); %%%%% CHOOSE ANY DATE YOU CARE ABOUT

%% Part 1:  Set up environment and Directories
save_dirsup=[save_dir,'\supplemental'];
disp(['Supplemental data files will be saved in: ',save_dirsup]);

%%%%%%%%%%%% Make a new directory if needed
if ~exist(save_dirsup, 'dir')
    mkdir(save_dirsup);
end

%% Part 2: Download observations from a single day
% Next, we will download a GLSEA data from the CoastWatch Great Lakes node THREDDS server 
% https://coastwatch.glerl.noaa.gov/satellite-data-products/great-lakes-surface-environmental-analysis-glsea/

%%%%%%%%%%%% Configure Model Download Parameters
url_glsea='https://apps.glerl.noaa.gov/thredds/fileServer/glsea_nc_3';

%%%%%%%%%%% Define datestrings and make filenames
yearstr = sprintf('%04d', year(date_of_interest));
monstr = sprintf('%02d', month(date_of_interest));
daystr = sprintf('%03d', day(date_of_interest,'dayofyear'));

filenamee=[yearstr,'_',daystr,'_glsea_sst.nc'];
url_download=[url_glsea,'/',yearstr,'/',monstr,'/',filenamee];
options=weboptions;options.Timeout=15; 

%%%%%%% Download GLSEA data file
%%%%%%% Add mechanism to retry in case there are network issues
max_retries=5;
retries=0;
while retries<max_retries
    try
        websave([save_dirsup,'\',filenamee],url_download,options);
        retries=max_retries+1;
    catch
        retries=retries+1;
        disp(['Connection Error: Retrying (',num2str(retries),'/',num2str(max_retries),')']);
    end
end

%% Part 3: Load Data and Investigate File Structure
%%%%%%%%%% check header structure for file
info=ncinfo([save_dirsup,'\',filenamee]);

% print long names of all variables in header structure
for k = 1:length(info.Variables)
    varname = info.Variables(k).Name;
    try
    dims = strjoin({info.Variables(k).Dimensions.Name}, ', ');
    catch
    dims = 'No dimensions';
    end
    if isfield(info.Variables(k).Attributes, 'Name')
        attrNames = {info.Variables(k).Attributes.Name};
        idx = find(strcmp(attrNames, 'long_name'), 1);
        if ~isempty(idx)
            long_name = info.Variables(k).Attributes(idx).Value;
        else
            long_name = 'No long_name attribute';
        end
    else
        long_name = 'No long_name attribute';
    end
    fprintf('%-20s dims: %-30s long_name: %s\n', varname, dims, long_name);
end

%%%%%% Load variables from glsea data
sst=ncread([save_dirsup,'\',filenamee],'sst');
lon=ncread([save_dirsup,'\',filenamee],'lon');
lat=ncread([save_dirsup,'\',filenamee],'lat');
time=ncread([save_dirsup,'\',filenamee],'time');
crs=ncread([save_dirsup,'\',filenamee],'crs');

%%%%%% convert time based on file attirbutes
date_glsea=datetime(1970,1,1,0,0,0)+seconds(time);

%% Part 4: Make a quick plot to make sure it worked...
figure;
pcolor(lon,lat,sst');shading flat;
xlabel('longitude');
ylabel('latitude');
cb=colorbar;
title(cb,'T(\circC)');
title(string(date_glsea));

%% Part 5: Create a Fancier Map...
%%%%%%% Define longitude and latitude bounds
minLat=min(lat);
maxLat=max(lat);
minLon=min(lon);
maxLon=max(lon);

%%%%%% Load basemap
% options include: 'darkwater', 'grayland', 'bluegreen', 'grayterrain', 
% 'colorterrain', 'landcover', 'streets', 'streets-light', 'streets-dark',
% 'satellite', 'topographic', 'none'
[A,RA] = readBasemapImage("streets-light",[minLat maxLat],[minLon maxLon]);

%%%%%% convert basemap image to latlon
[xGrid, yGrid] = worldGrid(RA);
[latGrid, lonGrid] = projinv(RA.ProjectedCRS, xGrid, yGrid);

%%%%%% Make a figure!
figure;
geoshow(latGrid, lonGrid, A);hold on;
pcolor(lon,lat,sst');shading flat;
xlim([minLon maxLon]);ylim([minLat maxLat]);
cb=colorbar; title(cb,'T(\circC)');
clim([0 15]);%set caxis limit
colormap('turbo');
xlabel('Longitude');
ylabel('Latitude');
title(append('GLSEA lake surface temperature: ', string(date_glsea)));

%% Part 6: Make another figure zoomed-in to look at grid
%%%%%%% Define longitude and latitude bounds
minLat=41.3;
maxLat=42.2;
minLon=-83.6;
maxLon=-82.2;

%%%%%% Load basemap
% options include: 'darkwater', 'grayland', 'bluegreen', 'grayterrain', 
% 'colorterrain', 'landcover', 'streets', 'streets-light', 'streets-dark',
% 'satellite', 'topographic', 'none'
[A,RA] = readBasemapImage("streets",[minLat maxLat],[minLon maxLon]);

%%%%%% convert basemap image to latlon
[xGrid, yGrid] = worldGrid(RA);
[latGrid, lonGrid] = projinv(RA.ProjectedCRS, xGrid, yGrid);

%%%%%% Make a figure!
figure;
geoshow(latGrid, lonGrid, A);hold on;
p=pcolor(lon,lat,sst');shading flat;
set(p,'EdgeColor','w')
xlim([minLon maxLon]);ylim([minLat maxLat]);
cb=colorbar; title(cb,'T(\circC)');
clim([0 15]);%set caxis limit
colormap('turbo');
xlabel('Longitude');
ylabel('Latitude');
title(append('GLSEA lake surface temperature: ', string(date_glsea)));