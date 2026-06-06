%% Hands-on Session 1: Downloading & Simple Analysis of Great Lakes Operational Forecast System (GLOFS)
%
% In this hands-on session, we will walk through the process of downloading, reading, and visualizing 
% the unstructured mesh hydrodynamic model outputs from the Lake Erie Operational Forecast System (LEOFS), 
% which is part of NOAA's Great Lakes Operational Forecast System (GLOFS).
% Estimated Time: 1 hour for core demonstration
%
%
% Created 5/25/2026
% Written by David Cannon (djcannon@umich.edu)
clear; close all; clc;
%% Part 0: Set Parameters For Demonstration
save_dir='C:\Users\cannon\Desktop\DataWorkshopCodes'; %%%%% SET THIS DIRECTORY FOR YOURSELF
date_of_interest=datetime(2026,5,1);

%% Part 1: Setup, Download, and Open a GLOFS file
%%%%%%%%%%%%%% 1.1 Download GLOFS data
% Download Great Lakes Operational Forecast System (GLOFS) output files from 
% Amazon s3 bucket. You can specify year, month, and day as you like. If 
% you'd like, you can also specify a system for another Great Lake.
% LEOFS: Lake Erie Operational Forecast System
% LMHOFS: Lake Michigan-Huron Operational Forecast System
% LSOFS: Lake Superior Operational Forecast System
% LOOFS: Lake Ontario Operational Forecast System

%%%%%%%%%%%% Configure Model Download Parameters
systemname = 'leofs';
yearstr = sprintf('%04d', year(date_of_interest));
monstr = sprintf('%02d', month(date_of_interest));
daystr = sprintf('%02d', day(date_of_interest));

%%%%%%%%%%%% Make a new directory if needed
save_dird=[save_dir,'\demo'];
disp(['Demonstration data files will be saved in: ',save_dird]);
if ~exist(save_dird, 'dir')
    mkdir(save_dird);
end

%%%%%%%%%%%% Download File: Nowcast Hour 000
filename = sprintf('%s.t00z.%s%s%s.fields.n000.nc', systemname, yearstr, monstr, daystr);
save_path = fullfile(save_dird, filename);
bucket = 'noaa-nos-ofs-pds';
key = sprintf('%s/netcdf/%s/%s/%s/%s', systemname, yearstr, monstr, daystr, filename);
s3_url=['s3://',bucket,'/',key];
copyfile(s3_url,save_path);

%% Part 2: Understand the FVCOM unstructured mesh
%%%%%%%%%%%%%%%%%% 2.1 Read the Data file
% Open and read the downloaded data file, and take a quick look at the data 
% contents by printing the dimension and variable long names. 
% There are a number of variables.
% open and read data by ncread and ncinfo
info = ncinfo(save_path);
% find the time reference to convert time units
timeloc=find(strcmp({info.Variables.Name},'time'));
timeatt=info.Variables(timeloc).Attributes(2).Value;
dateref=datetime(timeatt(15:end),'InputFormat','yyyy-MM-dd HH:mm:ss');

% read variables
time0 = ncread(save_path, 'time');
zeta = ncread(save_path, 'zeta');
u = ncread(save_path, 'u');
temp = ncread(save_path, 'temp');
time=dateref+seconds(time0);%%%%% Convert time units based on dateref...

% print initial time and dimensions
disp('------------------------------------')
disp(append('initial time: ', string(time(1))))
disp(['zeta: ', mat2str(size(zeta)), ' (node,str)'])
disp(['u: ', mat2str(size(u)), ' (nele,siglay)'])
disp(['temp: ', mat2str(size(temp)), ' (node,siglay)'])
disp('------------------------------------')
disp(' ')

% print long names of all variables
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

%% Part 2.2: Understanding the tirangular mesh, nodes, elements, and sigma layers
% Unlike data on a regular rectangular grid, FVCOM model output uses an unstructured 
% triangular mesh. This means the model domain is divided into many connected 
% triangles. Each triangle has nodes, which are the corner points of the triangles, 
% and elements, which represent the triangle cells themselves, often treated as 
% cell centers. In this LEOFS example, the grid contains 6,106 nodes and 11,509 elements
% ------------------------------------------------------------------------
% A single triangular element:
%             node
%              o
%             / \
%            /   \
%           /     \
%     node o-------o node
%
%    triangle cell = element
% ------------------------------------------------------------------------
% Different variables are stored at different locations on the mesh. Many scalar 
% variables, such as temperature (temp) and water surface elevation (zeta), are 
% defined at the nodes. In contrast, many vector variables, such as the eastward 
% and northward velocity components (u and v), are defined at the elements.
% ------------------------------------------------------------------------
% Node-based variable:
%temp, zeta
%
%         temp
%          o
%         / \
%        /   \
%  temp o-----o temp
%
%Element-based variable:
%u, v
%
%         o
%        / \
%       / ↑ \
%      / u,v \
%     o-------o
% ------------------------------------------------------------------------
% This example file contains only one time step, so each time-dependent variable 
% has a time dimension of length 1. The dimensions siglay and siglev describe 
% the model’s vertical coordinate system, called a sigma coordinate system, or 
% a terrain-following coordinate system. Instead of using fixed depth levels, 
% sigma coordinates divide the water column into layers based on fractions of 
% the total water depth. The siglay dimension represents the centers of the 
% vertical layers, while siglev represents the boundaries, or edges, between 
% those layers.
% ------------------------------------------------------------------------
% Sigma layers:
%
%Sea or lake surface
%────────────────  siglev
%       o           siglay
%────────────────  siglev
%       o           siglay
%────────────────  siglev
%       o           siglay
%────────────────  siglev
%Sea or lake floor
% ------------------------------------------------------------------------
% Some variables are effectively two-dimensional because they vary only 
% horizontally and in time, with no vertical variation (e.g., zeta, aice). 
% These variables do not include siglay or siglev as dimensions. Other 
% variables are three-dimensional because they vary with horizontal position, 
% time, and depth (e.g., temp, u, v). These variables include either the 
% siglay or siglev dimension.
%% Part 3: Plot Mesh and Surface Temperature
%%%%%%%%%%%%%%%%%%% 3.1 Plotting the Mesh
%%% Load variables for plotting...
nv=ncread(save_path, 'nv'); %%%% Triangulation matrix

%%%%%%%%%%%%%%%% lon/lat on nodes
lon_node=ncread(save_path, 'lon');
lon_node= mod(lon_node + 180, 360) - 180;
lat_node=ncread(save_path, 'lat');

%%%%%%%%%%%%%%%% lon/lat on elements
lon_ele=ncread(save_path, 'lonc');
lon_ele= mod(lon_ele + 180, 360) - 180;
lat_ele=ncread(save_path, 'latc');

%%%%%%%%%%%%%%%% Plot Triangular Mesh
figure;
triplot(double(nv), double(lon_node), double(lat_node), ...
    'Color', 'k', ...
    'LineWidth', 0.2);

axis equal;
xlabel('Longitude');
ylabel('Latitude');
title('FVCOM triangular mesh node-based');

%% -------------------------------------------------------------------------
% Next, we can make the triangular mesh plot easier to interpret by adding 
% a background map. A background map provides geographic context, so we can 
% see where the model grid is located relative to the Lake Erie shoreline 
% and surrounding land areas.

% There are several ways to add map features in Python. In this example, we 
% use GeoPandas together with a basemap/background map layer. Another option 
% is to use built-in map features from Cartopy, such as coastlines and land 
% polygons. However, the default Cartopy features can sometimes be too coarse 
% for regional applications like the Great Lakes, where shoreline details 
% are important. Using GeoPandas or a more detailed basemap can give us a 
% cleaner and more informative map for Lake Erie.
% -------------------------------------------------------------------------

% Define Lake Erie-ish bounding box in lon/lat  [You can change these!]
minLon = -83.6;
minLat =  41.3;
maxLon = -78.7;
maxLat =  43.0;

% Create figure and geographic axes
figure;
gx = geoaxes;
hold(gx, 'on');

% Set map extent
geolimits(gx, [minLat maxLat], [minLon maxLon]);

%%%%%%%%%%%%%%% Plot triangulation on map. This is more complicated for
%%%%%%%%%%%%%%% geoaxes, but it definitely looks nice. 
% Build triangulation object
TR = triangulation(double(nv), double(lon_node), double(lat_node));
% Extract unique triangle edges
E = edges(TR);
% Convert edges into NaN-separated line segments for geoplot
lon_edges = [lon_node(E(:,1)) lon_node(E(:,2)) nan(size(E,1),1)]';
lat_edges = [lat_node(E(:,1)) lat_node(E(:,2)) nan(size(E,1),1)]';
lon_edges = lon_edges(:);
lat_edges = lat_edges(:);
% Overlay mesh on basemap
geoplot(gx, lat_edges, lon_edges, 'w-', 'LineWidth', 0.2);

% Add satellite basemap
geobasemap(gx, 'satellite');

%% ------------------------------------------------------------------------
% Zooming over the western Lake Erie region. You are welcome to play with 
% other background maps. There are several options [see below]
% You are also welcome to play with the code to zoom over another areas.
% The supplemental_GLSEA.m provides an example to plot a regular grid 
% over the same area (based on GLSEA) for comparison with the triangular mesh.
% -------------------------------------------------------------------------
%%%%%%%%%%%% Set a slightly more zoomed-in version for Western Basin  [You can change these!]
minLon = -83.6;
minLat =  41.3;
maxLon = -82.2;
maxLat =  42.2;

% Create figure and geographic axes
figure;
gx = geoaxes;
hold(gx, 'on');

% Set map extent
geolimits(gx, [minLat maxLat], [minLon maxLon]);

%%%%%%%%%%%%%%% Plot triangulation on map. This is more complicated for
%%%%%%%%%%%%%%% geoaxes, but it definitely looks nice. 
% Build triangulation object
TR = triangulation(double(nv), double(lon_node), double(lat_node));
% Extract unique triangle edges
E = edges(TR);
% Convert edges into NaN-separated line segments for geoplot
lon_edges = [lon_node(E(:,1)) lon_node(E(:,2)) nan(size(E,1),1)]';
lat_edges = [lat_node(E(:,1)) lat_node(E(:,2)) nan(size(E,1),1)]';
lon_edges = lon_edges(:);
lat_edges = lat_edges(:);
% Overlay mesh on basemap
geoplot(gx, lat_edges, lon_edges, 'k-', 'LineWidth', 0.2);

% Add a different basemap...
% options include: 'darkwater', 'grayland', 'bluegreen', 'grayterrain', 
% 'colorterrain', 'landcover', 'streets', 'streets-light', 'streets-dark',
% 'satellite', 'topographic', 'none'
geobasemap(gx, 'streets');

%% 3.2 Plotting the Lake Surface Temperature
% Next, we will plot a map of lake surface temperature. 
% Let's start from a simple quick plot.
%%%%%%%% Load temperature variable
temp = ncread(save_path, 'temp');

%%%%%%%% select the time and layer index you care about
nindex = 1; %time index (choose first timestep)
siglay_index = 1; %vertical layer index (choose surface layer 1)
temp_surface = squeeze(temp(:, siglay_index));

%%%%%%%% Make the figure!
figure;
trisurf(double(nv),double(lon_node),double(lat_node),ones(size(lon_node)),...
    temp_surface,'EdgeColor', 'none');

view(2);
axis equal tight;
cb=colorbar;
title(cb,'T(\circC)')

xlabel('Longitude');
ylabel('Latitude');
title(append('FVCOM lake surface temperature: ', string(time(1))));

%% Now let's plot a nicer version, zoomed over western Lake Erie.
%%%%%%%%%%%% Set a slightly more zoomed-in version for Western Basin  [You can change these!]
minLon = -83.6;
minLat =  41.3;
maxLon = -82.2;
maxLat =  42.2;

%%%%%%%%%%%% Prepare basemap using another method. This is required if we
%%%%%%%%%%%% want to use surface patch objects in matlab
%%%%%% Load basemap
[A,RA] = readBasemapImage("satellite",[minLat maxLat],[minLon maxLon]);
%%%%%% convert basemap image to latlon
[xGrid, yGrid] = worldGrid(RA);
[latGrid, lonGrid] = projinv(RA.ProjectedCRS, xGrid, yGrid);

% Create figure!
figure;
geoshow(latGrid, lonGrid, A);hold on;
trisurf(double(nv),double(lon_node),double(lat_node),ones(size(lon_node)),...
    temp_surface,'EdgeColor', 'w');
xlim([minLon maxLon]);ylim([minLat maxLat]);
cb=colorbar; title(cb,'T(\circC)');
clim([0 15]);%set caxis limit
xlabel('Longitude');
ylabel('Latitude');
title(append('FVCOM lake surface temperature: ', string(time(1))));

%% Part 4: Overlay Surface Velocity Vector
% 4.1 Overaly velocity vectors
% Now, we will overlay velocity vectors for the lake surface current.

%%%%%%%%%%%% Set a slightly more zoomed-in version for Western Basin [You can change these!]
minLon = -83.6;
minLat =  41.3;
maxLon = -82.2;
maxLat =  42.2;

%%%%%%%%%%%% Prepare basemap using another method. This is required if we
%%%%%%%%%%%% want to use surface patch objects in matlab
%%%%%% Load basemap
[A,RA] = readBasemapImage("satellite",[minLat maxLat],[minLon maxLon]);
%%%%%% convert basemap image to latlon
[xGrid, yGrid] = worldGrid(RA);
[latGrid, lonGrid] = projinv(RA.ProjectedCRS, xGrid, yGrid);

%%%%% Prepare surface valocity vectors
temp = ncread(save_path, 'temp');
u = ncread(save_path, 'u');
v = ncread(save_path, 'v');
siglay_index = 1; %vertical layer index (choose surface layer 1)
u_surface = squeeze(u(:, siglay_index));
v_surface = squeeze(v(:, siglay_index));

%%%%% Create a mask to remove values outside lon/lat bounds
% Remember, velocity vectors are on element centers, so we need to use
% lon_ele and lat_ele
mask=(lon_ele>=minLon & lon_ele <=maxLon & ...
    lat_ele>=minLat & lat_ele <=maxLat & ...
    isfinite(u_surface) & isfinite(v_surface));
u_plot=u_surface(mask);
v_plot=v_surface(mask);
lon_plot=lon_ele(mask);
lat_plot=lat_ele(mask);

%%%%% set arrow scale and skip index
%%%%%%%% the skip index helps reduce the total number of arrows
arrow_scale=0.5;%larger makes larger arrows
skip_index=5;

% Create figure!
figure;
h=geoshow(latGrid, lonGrid, A, 'FaceAlpha', 0.75);hold on;
trisurf(double(nv),double(lon_node),double(lat_node),zeros(size(lon_node)),...
    temp_surface,'EdgeColor', 'w');
%%%%%%%%%%%%%% plot the arrow quivers
quiver(lon_plot(1:skip_index:end),lat_plot(1:skip_index:end),...
    arrow_scale*u_plot(1:skip_index:end),arrow_scale*v_plot(1:skip_index:end),...
    'b','AutoScale','off');
%%%%%%%%%%%%%% make a reference arrow
quiver(minLon+0.05*(maxLon-minLon),minLat+0.05*(maxLat-minLat),...
    arrow_scale.*0.3,arrow_scale.*0,'b','AutoScale','off');
text(minLon+0.05*(maxLon-minLon)+1.05*0.3*arrow_scale,...
    minLat+0.05*(maxLat-minLat),'0.3 m/s','Color','b');
xlim([minLon maxLon]);ylim([minLat maxLat]);
cb=colorbar; title(cb,'T(\circC)');
clim([0 15]);%set caxis limit
xlabel('Longitude');
ylabel('Latitude');
title(append('FVCOM LST and surface current: ', string(time(1))));

%% Optional: Vertical Transect of Temperature
% Until now, we focused on the lake surface data. It's often important to 
% understand what's going on in the sub-surface. A vertical transect is a 
% useful visualization to evaluate the thermal structure, thermocline and 
% temperature variations in horizontal and vertical directions. In an 
% unstructured mesh data, visualizing a vertical transect involves a few 
% steps, including defining a transect, extracting a nearest model nodes 
% (or elements if you are looking at a vector variable), and interpolating 
% data vertically.

% Clear old variables (this is in case you play around here)
clear temp_transect;
clear z_transect;

% Load all variables of interest 
temp = ncread(save_path, 'temp');
siglay = ncread(save_path,'siglay');
h = ncread(save_path,'h');
zeta = ncread(save_path,'zeta');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%% Prepare Transect Data for Plotting %%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Define Transect Endpoints [You can change these!]
start_lon = -83.4;
start_lat =  41.5;
end_lon   = -78.9;
end_lat   =  42.8;

% Number of points sampled along transect
ntransect = 500;

% Create lon/lat points along transect
transect_lon = linspace(start_lon, end_lon, ntransect);
transect_lat = linspace(start_lat, end_lat, ntransect);

% Create a "distance along transect" vector
dist=distance(transect_lat(1),transect_lon(1),transect_lat,transect_lon);
dist_km=deg2km(dist);
% compute z coordinate for each node
nsiglay=size(siglay,2);
z_node=repmat(zeta,1,nsiglay)+siglay.*repmat(h+zeta,1,nsiglay);

% Interpolate simulated temperatures to transect locations for each layer
for xx=1:size(temp,2)
    F=scatteredInterpolant(double(lon_node),double(lat_node),double(temp(:,xx)),'linear','none');
    temp_transect(:,xx)=F(transect_lon,transect_lat);
end

% Interpolate model depths to transect locations for each layer
for xx=1:size(z_node,2)
    F=scatteredInterpolant(double(lon_node),double(lat_node),double(z_node(:,xx)),'linear','none');
    z_transect(:,xx)=F(transect_lon,transect_lat);
end

% Interpolate surface and bottom elevations
F=scatteredInterpolant(double(lon_node),double(lat_node),double(h),'linear','none');
h_transect=F(transect_lon,transect_lat);
F=scatteredInterpolant(double(lon_node),double(lat_node),double(zeta),'linear','none');
zeta_transect=F(transect_lon,transect_lat);

% Do some manipulation of the array to add surface and bottom layers
z_plot=[zeta_transect' z_transect -h_transect'];
temp_plot=[temp_transect(:,1) temp_transect temp_transect(:,end)];


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%% Prepare Surface Map Data for Plotting %%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% Limits for lake map [You can change these!]
minLon = min(lon_node);
minLat = min(lat_node);
maxLon = max(lon_node);
maxLat =  max(lat_node);

%%%%%% Define Variables
sst=temp(:,1);%grab just the top layer for plotting

%%%%%% Load basemap
[A,RA] = readBasemapImage("satellite",[minLat maxLat],[minLon maxLon]);
%%%%%% convert basemap image to latlon
[xGrid, yGrid] = worldGrid(RA);
[latGrid, lonGrid] = projinv(RA.ProjectedCRS, xGrid, yGrid);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%% Create a Figure With Two Subplots %%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Plot settings
cmap = 'turbo';
nlevel=20; %number of contour levels for figure;
climit=[0 15];

% make the plot itself!
figure;
subplot(2,1,1);
geoshow(latGrid, lonGrid, A);hold on;
trisurf(double(nv),double(lon_node),double(lat_node),zeros(size(lon_node)),...
    temp_surface,'EdgeColor', 'None');
plot([start_lon end_lon],[start_lat end_lat],'k--','LineWidth',2);
xlim([minLon maxLon]);ylim([minLat maxLat]);
cb=colorbar; title(cb,'T(\circC)');colormap(cmap);
clim(climit);%set caxis limit
xlabel('Longitude');
ylabel('Latitude');
title(append('FVCOM lake surface temperature: ', string(time(1))));

subplot(2,1,2)
contourf(repmat(dist_km',1,nsiglay+2),z_plot,temp_plot, nlevels, "LineColor", "none");hold on;
plot(dist_km,-h_transect,'k-','LineWidth',2);
plot(dist_km,zeta_transect,'k--');
xlabel("Distance along transect [km]");
ylabel("Elevation [m]");
title("Vertical transect of water temperature");
grid on;grid minor;
cb=colorbar;colormap(cmap);
clim(climit);%set caxis limit
title(cb,'T(\circC)');
