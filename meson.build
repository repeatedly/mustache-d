project('mustache-d', 'd',
    meson_version: '>=0.45',
    license: 'BSL-1.0',
    version: '0.1.4'
)

project_soversion    = '0'

src_dir = include_directories('src/')
pkgc = import('pkgconfig')

mustache_src = [
    'src/mustache.d'
]
install_headers(mustache_src, subdir: 'd/mustache-d')

mustache_lib = library('mustache-d',
        [mustache_src],
        include_directories: [src_dir],
        install: true,
        version: meson.project_version(),
        soversion: project_soversion
)

pkgc.generate(name: 'mustache-d',
              libraries: mustache_lib,
              subdirs: 'd/mustache-d',
              version: meson.project_version(),
              description: 'Mustache template engine for D.'
)

# for use by others which embed this as subproject
mustached_dep = declare_dependency(
    link_with: [mustache_lib],
    include_directories: [src_dir]
)

# Tests
test_exe = executable('mustached_test',
        [mustache_src,
         'example/basic.d'],
        include_directories: [src_dir],
        d_unittest: true
)
test('mustache-d_test', test_exe, workdir: meson.current_source_dir())
