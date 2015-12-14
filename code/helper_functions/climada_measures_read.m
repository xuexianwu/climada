function measures = climada_measures_read(measures_filename)
% climada measures read import
% NAME:
%   climada_measures_read
% PURPOSE:
%   read the Excel file with the list of measures, usually called from
%   climada_entity_read. The field "cost" is
%   mandatory otherwise measures are not read.
%
%   This code allows single Excel files with measures
%   (and, if a tab damagefunctions exists, damage functions, and if a tab 
%   assets exists, regional_scope of measures) to be read
%   The user will then have to 'switch' measures in an already read and
%   encoded entity with the measures read here.
% CALLING SEQUENCE:
%   measures = climada_measures_read(measures_filename)
% EXAMPLE:
%   measures = climada_measures_read;
% INPUTS:
%   measures_filename: the filename of the Excel file with the measures
%       > promted for if not given
% OPTIONAL INPUT PARAMETERS:
% OUTPUTS:
%   measures: a structure, with the measures, including .regional_scope if
%   assets tab found wich specifies the regional_scope of a measure
% MODIFICATION HISTORY:
% David N. Bresch,  david.bresch@gmail.com, 20091228
% David N. Bresch,  david.bresch@gmail.com, 20130316, vulnerability->damagefunctions...
% Jacob Anz, j.anz@gmx.net, 20150819, use try statement to check for damagefunctions in excel sheet
% Lea Mueller, muellele@gmail.com, 20150907, add measures sanity check
% Lea Mueller, muellele@gmail.com, 20150915, add read the "assets" tab which defines the regional scope of one or more measures
% Lea Mueller, muellele@gmail.com, 20150916, omit nans in regional_scope 
% Lea Mueller, muellele@gmail.com, 20151016, delete nans in measures.name if there are invalid entries
% Lea Mueller, muellele@gmail.com, 20151119, use climada_assets_read, use spreadsheet_read instead of xls_read
% David Bresch, david.bresch@gmail.com, 20151119, bugfix for Octave to try/catch xlsinfo
% Jacob Anz, j.anz@gmx.net, 20151204, remove measures.damagefunctions if empty
%-
global climada_global
if ~climada_init_vars,return;end % init/import global variables

measures = []; %init
assets = [];

% poor man's version to check arguments
if ~exist('measures_filename','var'),measures_filename=[];end

% PARAMETERS
%

% prompt for measures_filename if not given
if isempty(measures_filename) % local GUI
    measures_filename=[climada_global.data_dir filesep 'measures' filesep '*.xls'];
    [filename, pathname] = uigetfile(measures_filename, 'Select measures:');
    if isequal(filename,0) || isequal(pathname,0)
        return; % cancel
    else
        measures_filename = fullfile(pathname,filename);
    end
end

% figure out the file type
[fP,fN,fE] = fileparts(measures_filename);

if isempty(fP) % complete path, if missing
    measures_filename=[climada_global.data_dir filesep 'entities' filesep fN fE];
    [fP,fN,fE] = fileparts(measures_filename);
end

if strcmp(fE,'.ods')
    % hard-wired sheet names for files of type .ods
    sheet_names = {'measures'};
else
    try
        % inquire sheet names from .xls
        [~,sheet_names] = xlsfinfo(measures_filename);
    catch
        sheet_names = {'measures'};
    end
end

try
    % read measures
    % --------------------
    for sheet_i = 1:length(sheet_names) % loop over tab (sheet) names
        if strcmp(sheet_names{sheet_i},'measures')
            measures = climada_spreadsheet_read('no',measures_filename,'measures',1);
            % measures = climada_xlsread('no',measures_filename,'measures',1);
        end
    end % sheet_i
    if isempty(measures)
        fprintf('No sheet "measures" found, just reading the first sheet.\n')
        measures = climada_spreadsheet_read('no',measures_filename,1);
    end 
    
catch ME
    fprintf('WARN: no measures data read, %s\n',ME.message)
end

% .cost is mandatory
if ~isfield(measures,'cost')
    fprintf('Error: no cost column in measures tab, aborted\n')
    measures= [];
    if strcmp(fE,'.ods') && climada_global.octave_mode
        fprintf('> make sure there are no cell comments in the .ods file, as they trouble odsread\n');
    end
    return
end
    
try 
    measures.damagefunctions = climada_damagefunctions_read(measures_filename);
    % measures.damagefunctions = climada_xlsread('no',measures_filename,'damagefunctions',1);
    fprintf('Special damagefunctions for measures found\n')
    % delete nans if there are
    if isempty(measures.damagefunctions)
        measures = rmfield(measures, 'damagefunctions');
    else        
        measures.damagefunctions = climada_entity_check(measures.damagefunctions,'DamageFunID');
    end
catch
    fprintf('No damagefunction sheet found\n')
end

% rename vuln_map, since otherwise climada_measures_encode does not treat it
if isfield(measures,'vuln_map'),measures.damagefunctions_map=measures.vuln_map;measures=rmfield(measures,'vuln_map');end

% check for OLD naming convention, vuln_MDD_impact_a -> MDD_impact_a
if isfield(measures,'vuln_MDD_impact_a'),measures.MDD_impact_a=measures.vuln_MDD_impact_a;measures=rmfield(measures,'vuln_MDD_impact_a');end
if isfield(measures,'vuln_MDD_impact_b'),measures.MDD_impact_b=measures.vuln_MDD_impact_b;measures=rmfield(measures,'vuln_MDD_impact_b');end
if isfield(measures,'vuln_PAA_impact_a'),measures.PAA_impact_a=measures.vuln_PAA_impact_a;measures=rmfield(measures,'vuln_PAA_impact_a');end
if isfield(measures,'vuln_PAA_impact_b'),measures.PAA_impact_b=measures.vuln_PAA_impact_b;measures=rmfield(measures,'vuln_PAA_impact_b');end            

% delete nans if there are invalid entries
measures = climada_entity_check(measures,'name');

try 
    % see if assets tab is provided, which defines the regional scope of
    % one or more measures
    assets = climada_assets_read(measures_filename,'NOENCODE');
    %assets = climada_xlsread('no',measures_filename,'assets',1);
    %fprintf('asset sheet found\n');
end
   

if ~isempty(assets)
      
    % number of measures
    n_measures = numel(measures.name);
    
    % initialize logical index to define the regional scope of measures
    measures.regional_scope = ones(length(assets.Value),n_measures);
    
    % get all fieldnames in the structure "assets"
    asset_columns = fieldnames(assets);
    
    % get measures names, without brackets and replace empty spaces with underline
    measures_names = strrep(strrep(strrep(measures.name,' ','_'),'(',''),')','');
    
    % find those names in the asset_columns
    has_scope = ismember(measures_names,asset_columns);
    
    if any(has_scope)
        has_scope = find(has_scope);
        fprintf('Regional scope of measures found\n');
        
        % loop over measures that have a regional scope and save in matrix
        % measures.regional_scope
        for scope_i = 1:numel(has_scope)
            scope = getfield(assets, measures_names{has_scope(scope_i)});     
            scope(isnan(scope)) = 0;
            measures.regional_scope(:,has_scope(scope_i)) = scope;
        end 
    end %has_scope
    
    % create logical 
    measures.regional_scope = logical(measures.regional_scope);
end

% encode measures
measures = climada_measures_encode(measures);

% sanity check for measures
climada_measures_check(measures);

% save measures as .mat file for fast access
% but we re-read form .xls each time this code is called
[fP,fN] = fileparts(measures_filename);
save([fP filesep fN],'measures')

return