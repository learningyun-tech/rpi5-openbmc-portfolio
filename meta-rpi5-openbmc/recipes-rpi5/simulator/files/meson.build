project(
  'rpi5-openbmc-simulator',
  'cpp',
  default_options: ['cpp_std=c++23', 'warning_level=3', 'werror=true'],
  license: 'Apache-2.0',
  version: '1.0.0',
  meson_version: '>=1.1.1',
)

add_project_arguments(
  '-DBOOST_ERROR_CODE_HEADER_ONLY',
  '-DBOOST_SYSTEM_NO_DEPRECATED',
  '-DBOOST_ASIO_NO_DEPRECATED',
  '-DBOOST_ALL_NO_LIB',
  language: 'cpp',
)

boost_dep = dependency('boost', include_type: 'system')
sdbusplus_dep = dependency('sdbusplus')

executable(
  'rpi5-openbmc-simulator',
  'main.cpp',
  dependencies: [boost_dep, sdbusplus_dep],
  install: true,
)
