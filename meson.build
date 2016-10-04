project('mustache-d', 'd')

project_version      = '0.1.1'
project_soversion    = '0'

src_dir = include_directories('src/')
pkgc = import('pkgconfig')

mustache_src = [
    'src/mustache.d'
]
install_headers(mustache_src, subdir: 'd/mustache-d')

mustache_lib = static_library('mustache-d',
        [mustache_src],
        include_directories: [src_dir],
        install: true,
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'mustache-d',
              libraries: mustache_lib,
              subdirs: 'd/mustache-d',
              version: project_version,
              description: 'Mustache template engine for D.'
)
