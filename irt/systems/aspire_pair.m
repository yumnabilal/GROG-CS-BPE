  function args = aspire_pair(sg, ig, varargin)
%|function args = aspire_pair(sg, ig, [options])
%| see ASPIRE users guide under tech. reports on web page for details
%|
%| options
%|	'scale'		default: 0 - transmission scaling
%|	'strip_width'	default: from sg.strip_width
%|			or, if empty, then 0 (line integrals)
%|	'support'	default: 'all'
%|			('all' works ok because Gtomo2_dscmex uses ig.mask)
%|			logical_array: write to temporary file and use
%|			'array' - uses ig.mask in Gtomo2_wtmex / wtfmex
%|	'system'	default: [] - determine from sg.type
%|	'tiny'		default: [] - defer to aspire default
%|	'dscfile'	if nonempty, write info to this file. default: ''
%| Copyright 2005-12-14, Jeff Fessler, University of Michigan

if nargin == 1 && streq(sg, 'test'), aspire_pair_test, return, end

if nargin < 2, help(mfilename), error(mfilename), end

opt.scale = 0; % default: transmission scaling
opt.strip_width = []; % see below
opt.support = 'all';
opt.system = [];
opt.tiny = [];
opt.dscfile = '';
opt = vararg_pair(opt, varargin);

if isempty(opt.strip_width) % default
	if isfield(sg, 'strip_width') && ~isempty(sg.strip_width)
		opt.strip_width = sg.strip_width; % inherit
	else
		opt.strip_width = 0; % default of last resort: line integrals
	end
end

% if support is given as a logical array, write to file
if ~ischar(opt.support)
	if ~islogical(opt.support)
		fail('support must be char or logical')
	end
	file = [test_dir 'aspire-pair-mask.fld'];
	fld_write(file, opt.support);
	opt.support = ['file ' file];
end

if isempty(opt.system)
	if streq(sg.type, 'fan') && sg.dfs == 0
		opt.system = 14;
	elseif streq(sg.type, 'fan') && sg.dfs == inf
		opt.system = 13;
	elseif streq(sg.type, 'par')
		opt.system = 2;
	else
		error 'default not done'
	end
end

if streq(opt.system, '3l')
	args = aspire_pair_3l(sg, ig);
return
end

switch opt.system

case 2
	args = {};
	if ~isempty(opt.tiny)
		args = {'tiny', opt.tiny};
	end
	args = arg_pair('system', opt.system, 'nx', ig.nx, 'ny', ig.ny, ...
		'nb', sg.nb, 'na', sg.na, 'support', opt.support, ...
		'orbit', sg.orbit, 'orbit_start', sg.orbit_start, ...
		'pixel_size', ig.dx, 'ray_spacing', sg.d, ...
		'flip_y', -ig.dy / ig.dx, ...
		'scale', opt.scale, ...
		'strip_width', opt.strip_width, ...
		'offset_even', sg.offset, args{:});

case 9
	args = arg_pair('system', opt.system, 'nx', ig.nx, 'ny', ig.ny, ...
		'nb', sg.nb, 'na', sg.na, 'support', opt.support, ...
		'orbit', sg.orbit, 'orbit_start', sg.orbit_start, ...
		'pixel_size', ig.dx, 'ray_spacing', sg.d, ...
		'flip_y', -ig.dy / ig.dx, ...
		'offset_even', sg.offset, ...
		'scale', opt.scale);
%		'strip_width', opt.strip_width, ...

case 13
	if sg.source_offset ~= 0. || sg.offset ~= 0.
		error 'source_offset and offset_s not tested for flat fan'
		% i tried to test it with ellipse_sino test,
		% but failed to get aspire to match matlab
	end
	args = arg_pair('system', opt.system, 'nx', ig.nx, 'ny', ig.ny, ...
		'nb', sg.nb, 'na', sg.na, 'support', opt.support, ...
		'orbit', sg.orbit, 'orbit_start', sg.orbit_start, ...
		'pixel_size', ig.dx, 'ray_spacing', sg.d, ...
		'strip_width', opt.strip_width, ...
		'src_det_dis', sg.dsd, ...
		'obj2det_x', sg.dod, 'obj2det_y', sg.dod, ...
		'scale', opt.scale);
%		'source_offset', sg.offset, ... % trick: source=channel for flat
%		'source_offset', sg.source_offset, ...

case 14
	args = arg_pair('system', opt.system, 'nx', ig.nx, 'ny', ig.ny, ...
		'nb', sg.nb, 'na', sg.na, 'support', opt.support, ...
		'orbit', sg.orbit, 'orbit_start', sg.orbit_start, ...
		'pixel_size', ig.dx, 'ray_spacing', sg.d, ...
		'strip_width', opt.strip_width, ...
		'src_det_dis', sg.dsd, ...
		'obj2det_x', sg.dod, 'obj2det_y', sg.dod, ...
		'scale', opt.scale, ...
		'source_offset', 0, ...
		'channel_offset', sg.offset);

otherwise
	error 'unknown system'
end

% print to .dsc file if requested
if ~isempty(opt.dscfile)
	fid = fopen(opt.dscfile, 'w');
	fprintf(fid, '# from %s\n', mfilename);
	for ii=1:nrow(args)
		fprintf(fid, '%s\n', args(ii,:));
	end
	fclose(fid);
%	eval(['!cat ' opt.dscfile])
end


%
% aspire_pair_3l()
%
function args = aspire_pair_3l(cg, ig);

if ~isinf(cg.dfs), fail('only flat detector done'), end

if any(cg.zshifts) % helix
	if ~isempty(cg.user_zshifts), fail('sorry, user_zshifts not done'), end
	args = ['3l@helix-flat-tsa:dx=%g,dy=%g,dz=%g,cx=%g,cy=%g,cz=%g,' ...
		'ns=%d,nt=%d,na=%d,ds=%g,dt=%g,cs=%g,ct=%g,' ...
		'dso=%g,dod=%g,orbit=%g,orbit_start=%g,', ...
		'pitch=%g,offset_z=%g'];
	args = sprintf(args, ...
		ig.dx, ig.dy, ig.dz, ...
		ig.offset_x, ig.offset_y, ig.offset_z, ...
		cg.ns, cg.nt, cg.na, ...
		cg.ds, cg.dt, ...
		cg.offset_s, cg.offset_t, ...
		cg.dso, cg.dod, ...
		cg.orbit, cg.orbit_start, ...
		cg.pitch, cg.offset_z);

else % axial
	args = ['3l@axial-flat-tsa:dx=%g,dy=%g,dz=%g,cx=%g,cy=%g,cz=%g,' ...
		'ns=%d,nt=%d,na=%d,ds=%g,dt=%g,cs=%g,ct=%g,' ...
		'dso=%g,dod=%g,orbit=%g,orbit_start=%g'];
	args = sprintf(args, ...
		ig.dx, ig.dy, ig.dz, ...
		ig.offset_x, ig.offset_y, ig.offset_z, ...
		cg.ns, cg.nt, cg.na, ...
		cg.ds, cg.dt, ...
		cg.offset_s, cg.offset_t, ...
		cg.dso, cg.dod, ...
		cg.orbit, cg.orbit_start);
end

if 0 % old usage
	args = '3l@%g,%g,%d,%d,%g,%g,%g,%g,%g,%g,%g,%g@-@-2d,%d,%g,%g';
	args = sprintf(args, ...
		cg.dso / ig.dx, cg.dod / ig.dx, ...
		cg.nt, cg.ns, ... % trick: switch ns,nt
		cg.dt / ig.dx, cg.ds / ig.dx, ... % trick: switch ds,dt
		ig.dz / ig.dx, ...
		ig.offset_x, ig.offset_y, ig.offset_z, ...
		cg.offset_t, cg.offset_s, ... % trick: switch offset
		cg.na, cg.orbit, cg.orbit_start);
end


%
% aspire_pair_test()
%
function aspire_pair_test
sg = sino_geom('par', 'nb', 100);
ig = image_geom('nx', 64, 'dx', 1);
args = aspire_pair(sg, ig, 'dscfile', [test_dir 'test.dsc'])
