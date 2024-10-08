  function ob = Gcone(cg, ig, varargin)
%|function ob = Gcone(cg, ig, [options])
%|
%| Construct Gcone object, for 3D cone-beam or helical cone-beam
%| forward and back-projection.  Works with flat detectors or 3rd-gen CT arcs.
%|
%| in
%|	cg	ct_geom object (scanner geometry)
%|	ig	image_geom object (recon grid dimensions, FOV and mask)
%|
%| option
%|	'type'		'pd1' : basic pixel-driven (default - not very good)
%|			'nn1' : nearest-neighbor pixel-driven (not much better)
%|			'user' : user must provide 'mexfun'
%|			'dd1' : distance-driven (GE's patented method, UM only)
%|			'dd2' : new improved DD version from GE (UM only)
%|			...
%|	'is_ns_nt'	1 (default) for [ns nt na] or 0 for [nt ns na]
%|	'nthread'	# of threads, default: jf('ncore')
%|	'mexfun'	only needed for 'user' option, see usage in code.
%|	'mexarg'	cell array of optional arguments to mexfun
%|	'scale'		scale mex output by this. (default: [])
%|	'use_hct2'	call hct2 instead of mex (UM only)
%|
%| out
%|	ob [nd np]	np = sum(mask(:)), so it is already "masked"
%|			nd = [ns * nt * na] if is_ns_nt = 1
%|			nd = [ns * na * nt] if is_ns_nt = 0
%|
%| For more help, type 'dd_ge1_mex' or 'dd_ge2_mex' and see Gcone_test.m
%|
%| Copyright 2005-5-19, Jeff Fessler, University of Michigan

if nargin == 1 & streq(cg, 'test'), run_mfile_local Gcone_test, return, end
if nargin < 2, help(mfilename), error(mfilename), end

% option defaults
arg.type = 'pd1'; % todo: replace with better way
arg.chat = false;
arg.scale = [];
arg.is_ns_nt = true; % default: [ns nt na] (channel fastest, row, view slowest)
arg.nthread = jf('ncore');
arg.mexfun = [];
arg.mexarg = {};
arg.use_hct2 = false; % UM only

% options specified by name/value pairs
arg = vararg_pair(arg, varargin);

% initialize generic geometry
arg = Gcone_setup(cg, ig, arg);

arg.flip_x = false;
arg.flip_y = false;
arg.flip_z = false;

arg.cg = cg;
arg.ig = ig;
arg.nd = cg.ns * cg.nt * cg.na;
arg.np = sum(ig.mask(:));
dim = [arg.nd arg.np]; % trick: make it masked by default!

% case specific setup
switch arg.type
case {'nn1', 'pd1', 'sf1'}
	arg.mexfun = Gcone_which_mex(arg.chat);
	arg.mexstr_back = ['cbct,' arg.type ',back'];
	arg.mexstr_proj = ['cbct,' arg.type ',proj'];
	arg.mask2 = uint8(sum(ig.mask, 3) > 0);

case 'user'
	if isempty(arg.mexfun), fail('mexfun required'), end

case 'dd1' % 1st GE version of DD (UM only)
	arg.mexfun = @dd_ge1_mex;
	arg = Gcone_setup_dd1(cg, ig, arg);
	arg.flip_x = arg.ig.dx < 0;
	arg.flip_y = arg.ig.dy > 0;
	arg.flip_z = arg.ig.dz < 0;

case 'dd2' % 2nd GE version of DD (UM only)
	arg.mexfun = @dd_ge2_mex;
	arg = Gcone_setup_dd2(cg, ig, arg);
	arg.flip_x = arg.ig.dx < 0;
	arg.flip_y = arg.ig.dy > 0;
	arg.flip_z = arg.ig.dz < 0;

otherwise
	fail('type %s unknown', arg.type)
end

if arg.is_ns_nt
	arg.odim = [arg.cg.ns arg.cg.nt arg.cg.na];
else
	arg.odim = [arg.cg.nt arg.cg.ns arg.cg.na];
end

%
% build Fatrix object
%
ob = Fatrix(dim, arg, 'caller', 'Gcone', ...
	'forw', @Gcone_forw, 'back', @Gcone_back, ...
	'mtimes_block', @Gcone_mtimes_block);


%
% Gcone_which_mex()
% pick cbct_mex if available (for development) otherwise use jf_mex
%
function fun = Gcone_which_mex(chat)
if exist('cbct_mex') == 3
	fun = @cbct_mex;
	if chat, printm 'using cbct_mex', end
elseif exist('jf_mex') == 3
	fun = @jf_mex;
else
	fail('cannot find jf_mex or cbct_mex')
end


%
% Gcone_setup()
%
function arg = Gcone_setup(cg, ig, arg)

arg.voxel_size = abs([ig.dx ig.dy ig.dz]);
arg.img_offset = single([ig.offset_x ig.offset_y ig.offset_z]);
arg.angles = single(cg.ar);

if isempty(cg.zshifts) || all(cg.zshifts == 0)
	arg.zshifts = zeros(cg.na, 1, 'single'); % axial default
else
	printm('warn: zshifts not tested!!!!!')
	arg.zshifts = single(cg.zshifts); % helical
end


%
% Gcone_setup_dd2()
%
function arg = Gcone_setup_dd2(cg, ig, arg)

arg = Gcone_setup_dd1(cg, ig, arg); % trick: recycle most of the setup of dd1

% caution: z normalization differs for dd2:
zscale = arg.voxel_size(3) / arg.voxel_size(1);
arg.zds = arg.zds * zscale;
arg.zshifts = arg.zshifts * zscale;
arg.pos_source(3) = arg.pos_source(3) * zscale; 

arg.img_offset(1) = -arg.img_offset(1); % found empirically for dx > 0
arg.img_offset(3) = -arg.img_offset(3) * zscale; % found empirically for dz > 0


%
% Gcone_setup_dd1()
% note: dd1 code uses voxel_size normalized units
%
function arg = Gcone_setup_dd1(cg, ig, arg)

if abs(ig.dx) ~= abs(ig.dy)
	error 'need |dx| = |dy|'
end

% default "scale" is xy voxel_size for dd1
if isempty(arg.scale)
	arg.scale = arg.voxel_size(1);
end

arg.pos_source = [0 cg.dso 0];

%
% detector sample locations
%

arg.ss = cg.s; % sample centers along arc length of detector

arg.zds = cg.t;
if ~isequal(arg.zds, sort(arg.zds))
	error 'z positions of detectors, i.e., cg.t, must be ascending'
end

if isinf(cg.dso)
	error 'parallel beam not done'

% cone-beam with flat detector
elseif isinf(cg.dfs)
	arg.xds = arg.ss;
	arg.yds = repmat(-cg.dod, [1 cg.ns]);

% 3rd generation multi-slice CT with focal point of arc at isocenter
else
	if cg.dfs ~= 0, warning 'dis_foc_src nonzero?', end
	dis_foc_det = cg.dfs + cg.dsd; % 3rd gen
	t = arg.ss / dis_foc_det; % angle in radians
	arg.xds = dis_foc_det * sin(t);
	arg.yds = cg.dso - dis_foc_det * cos(t);
end


% dd1 code expects in normalized pixel units
arg.xds = single(arg.xds / arg.voxel_size(1));
arg.yds = single(arg.yds / arg.voxel_size(2));
arg.zds = single(arg.zds / arg.voxel_size(3)); % z pixels
arg.zshifts = single(arg.zshifts / arg.voxel_size(3)); % z pixels
arg.pos_source = single(arg.pos_source ./ arg.voxel_size);
arg.dz_dx = single(arg.voxel_size(3) / arg.voxel_size(1));


%
% Gcone_forw(): y = G * x
%
function y = Gcone_forw(arg, x)
y = Gcone_mtimes_block(arg, 0, x, 1, 1); % full projection


%
% Gcone_back(): x = G' * y
%
function x = Gcone_back(arg, y)
x = Gcone_mtimes_block(arg, 1, y, 1, 1); % full back-projection


%
% flipper3()
%
function x = flipper3(x, arg);
if arg.flip_x < 0
	x = flipdim(x, 1);
end

if arg.flip_y > 0
	x = flipdim(x, 2);
end

if arg.flip_z < 0
	x = flipdim(x, 3);
end

%
% Gcone_mtimes_block_hct2()
% forward projector based on called unix binary "hct2"
%
function y = Gcone_mtimes_block_hct2(arg, is_transpose, x, istart, nblock)

if is_transpose, fail 'hct2 back not done', end
if istart ~= 1 || nblock ~= 1, fail 'hct2 block not done', end
f.hct2 = 'hct2';
f.x = [test_dir 'gcone-hct-x.fld'];
f.y = [test_dir 'gcone-hct-y.fld'];
f.m = [test_dir 'gcone-hct-mask.fld'];
if exist(f.x, 'file'), delete(f.x), end
if exist(f.y, 'file'), delete(f.y), end
if exist(f.m, 'file'), delete(f.m), end
fld_write(f.x, x)
fld_write(f.m, arg.ig.mask);
com = [f.hct2 ' chat 10 what proj nthread 8' ...
	sprintf(' sysmod %s', arg.type) ...
	sprintf(' file_yi %s file_init %s', f.y, f.x) ...
	sprintf(' file_mask %s', f.m) ...
	hct_arg(arg.cg, arg.ig) ...
];
tmp = os_run(com);
y = fld_read(f.y, 'raw', 1);


%
% Gcone_mtimes_block()
%
function y = Gcone_mtimes_block(arg, is_transpose, x, istart, nblock)

if arg.use_hct2 % trick: handle hct2 case
	y = Gcone_mtimes_block_hct2(arg, is_transpose, x, istart, nblock);
return
end

if is_transpose
	y = Gcone_block_back(arg, x, istart, nblock);
else
	y = Gcone_block_forw(arg, x, istart, nblock);
end


%
% Gcone_block_forw()
%
function y = Gcone_block_forw(arg, x, istart, nblock)

[x ei] = embed_in(x, arg.ig.mask, arg.np);

x = flipper3(x, arg);
x = permute(x, [3 1 2 4]); % trick: dd1|dd2|nn1|pd1 code wants z dim first!

ia = istart:nblock:arg.cg.na;

switch arg.type
case {'dd1', 'dd2'}

	y = arg.mexfun('proj3', arg.pos_source, arg.xds, arg.yds, arg.zds, ...
		arg.dz_dx, arg.img_offset, int32(arg.nthread), ...
		arg.angles(ia), arg.zshifts(ia), ...
		single(x), arg.mexarg{:});

otherwise % nn1 pd1 sf1

	% codo: could add is_ns_nt here to save permute at end
	s = @(x) single(x);
	y = arg.mexfun(arg.mexstr_proj, ...
		int32([arg.cg.ns arg.cg.nt length(ia)]), ...
		s([arg.ig.dx arg.ig.dy arg.ig.dz]), ...
		s([arg.ig.offset_x arg.ig.offset_y arg.ig.offset_z]), ...
		arg.mask2, ...
		s(arg.cg.dso), s(arg.cg.dsd), s(arg.cg.dfs), ...
		s([arg.cg.ds arg.cg.dt]), ...
		arg.angles(ia), ...
		s(arg.cg.offset_s), ...
		s(arg.cg.offset_t), ...
		arg.zshifts(ia), ...
		s(x), ...
		int32(arg.nthread), ...
		arg.mexarg{:});

end

y = double6(y);
if ~isempty(arg.scale)
	y = y * arg.scale;
end
if arg.is_ns_nt
	y = permute(y, [2 1 3 4]); % dd1|dd2|nn1|pd1|sf1 code makes [nt ns na]
end

y = ei.shape(y);


%
% Gcone_block_back()
%
function x = Gcone_block_back(arg, y, istart, nblock)

ia = istart:nblock:arg.cg.na;

[y eo] = embed_out(y, [arg.odim(1:end-1) length(ia)]); % [(M) *L]

if ~isempty(arg.scale)
	y = y * arg.scale;
end
if arg.is_ns_nt
	y = permute(y, [2 1 3 4]); % dd1|dd2|nn1|pd1|sf1 code wants [nt ns na]
end

switch arg.type
case {'dd1', 'dd2'}

	x = arg.mexfun('back3', arg.pos_source, arg.xds, arg.yds, arg.zds, ...
		arg.dz_dx, arg.img_offset, int32(arg.nthread), ...
		arg.angles(ia), arg.zshifts(ia), ...
		single(y), int32([arg.ig.nz arg.ig.nx arg.ig.ny]), ...
		arg.mexarg{:});

otherwise % nn1 pd1 sf1

	% codo: could add is_ns_nt here to save permute at end
	s = @(x) single(x);
	x = arg.mexfun(arg.mexstr_back, ...
		int32([arg.ig.nx arg.ig.ny arg.ig.nz]), ...
		s([arg.ig.dx arg.ig.dy arg.ig.dz]), ...
		s([arg.ig.offset_x arg.ig.offset_y arg.ig.offset_z]), ...
		arg.mask2, ...
		s(arg.cg.dso), s(arg.cg.dsd), s(arg.cg.dfs), ...
		s([arg.cg.ds arg.cg.dt]), ...
		arg.angles(ia), ...
		s(arg.cg.offset_s), ...
		s(arg.cg.offset_t), ...
		arg.zshifts(ia), ...
		s(y), ...
		int32(arg.nthread), ...
		arg.mexarg{:});

end

x = double6(x);
x = permute(x, [2 3 1 4]); % trick: dd1|dd2|nn1|pd1|sf1 code puts z dim first!
x = flipper3(x, arg);

x = x .* repmat(arg.ig.mask, [1 1 1 size(y,4)]); % trick: apply mask

x = eo.shape(x, arg.ig.mask, arg.np);
