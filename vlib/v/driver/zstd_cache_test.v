module driver

import os
import v.gen.c as cgen
import v.flat
import v.modulecache

fn test_shipped_zstd_cache_owner_tracks_implementation() ! {
	source := os.real_path(os.join_path(@VEXEROOT, 'thirdparty', 'zstd', 'zstd.c'))
	text := os.read_file(source)!
	assert v3_cache_native_input_has_program_owner(source, text, @VEXEROOT)
	assert !v3_cache_native_input_has_program_owner(source, 'unrecognized source', @VEXEROOT)
	assert !v3_cache_native_input_has_program_owner(os.join_path(@VEXEROOT, 'other.c'), text, @VEXEROOT)
	inputs := cgen.CacheNativeInputs{
		module_inputs: {
			'zstd': [source]
		}
		native_paths:  {
			source: true
		}
	}
	closure := v3_native_input_closure(&inputs, @VEXEROOT, true, '')
	assert closure.unassignable == ''
	assert source in closure.inputs['zstd']
}

fn test_native_preprocessed_type_boundaries_and_config_overrides() {
	source := 'enum { QOS_NORMAL = 1 }; typedef unsigned int qos_class_t;'
	assert !modulecache.c_source_is_replicable(source)
	assert modulecache.c_source_is_replicable(v3_split_native_declaration_lines(source))
	literals := 'static const char* message = "}; typedef"; /* }; */'
	assert v3_split_native_declaration_lines(literals).contains('"}; typedef"')
	assert v3_split_native_declaration_lines(literals).contains('/* }; */')
	mut ast := flat.FlatAst.new()
	assert v3_mbedtls_default_header_context(ast, ['-I/vendor/include'])
	for flags in [['-D', 'MBEDTLS_CONFIG_FILE="custom.h"'], ['-UMBEDTLS_CONFIG_FILE'],
		['-include', 'custom.h'], ['-imacroscustom.h'], ['-Wp,-DPSA_WANT_ALG_SHA_256=1']] {
		assert !v3_mbedtls_default_header_context(ast, flags)
	}
}

fn test_native_config_override_logical_directives() {
	assert v3_native_text_overrides_mbedtls('# define\tMBEDTLS_CONFIG_FILE "custom.h"')
	assert v3_native_text_overrides_mbedtls('#define MBEDTLS_\\\nCONFIG_FILE "custom.h"')
	assert v3_native_text_overrides_mbedtls('#define MBED\\\nTLS_CONFIG_FILE "custom.h"')
	assert v3_native_text_overrides_mbedtls('#define P\\\r\nSA_CONFIG_FILE "custom.h"')
	assert v3_native_text_overrides_mbedtls('#undef PSA_WANT_ALG_SHA_256')
	assert v3_native_text_overrides_mbedtls('/* context */ #define MBEDTLS_CONFIG_FILE "custom.h"')
	assert !v3_native_text_overrides_mbedtls('#define OTHER_CONFIG "custom.h"')
	mut ast := flat.FlatAst.new()
	ast.add_node(flat.Node{ kind: .directive, value: 'define', typ: 'MBEDTLS_CONFIG_FILE "custom.h"' })
	assert !v3_mbedtls_default_header_context(&ast, [])
}

fn test_transitive_native_configuration_override_is_not_default() {
	path := os.join_path(os.dir(@FILE), 'testdata', 'native_config', 'outer.h')
	mut active := map[string]bool{}
	mut expanded := map[string]bool{}
	source, complete := v3_expand_shipped_native_file(path, [], @VEXEROOT, true,
		mut active, mut expanded)
	assert complete
	assert expanded.len == 2
	assert v3_native_text_overrides_mbedtls(source)
}
