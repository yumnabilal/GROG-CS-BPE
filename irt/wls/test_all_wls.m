% test_all_wls.m

list = {
	'pwls_sps_os_test'
	'pwls_sps_example'
	'pwls_sps_zoom'
	'qpwls_qn_test'
	'qpwls_sps_example'
	'qpwls_pcg1_test'
	'wls_grpr_test'
	'wls_pcg_test'
	'pwls_gca_test'
	'qpwls_pcg2_test'
%	'qpwls_art2_vs_sps'	% very slow!
};

run_mfile_local(list)
%run_mfile_local(list, 'draw', 1, 'pause', 1)
