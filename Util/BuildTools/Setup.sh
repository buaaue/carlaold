#! /bin/bash

# ==============================================================================
# -- Set up environment --------------------------------------------------------
# ==============================================================================

command -v /usr/bin/clang++-6.0 >/dev/null 2>&1 || {
  echo >&2 "clang 6.0 is required, but it's not installed.";
  echo >&2 "make sure you build Unreal Engine with clang 6.0 too.";
  exit 1;
}

export CC=/usr/bin/clang-6.0
export CXX=/usr/bin/clang++-6.0

source $(dirname "$0")/Environment.sh

mkdir -p ${CARLA_BUILD_FOLDER}
pushd ${CARLA_BUILD_FOLDER} >/dev/null

# ==============================================================================
# -- Get and compile libc++ ----------------------------------------------------
# ==============================================================================

LLVM_BASENAME=llvm-6.0-ex

LLVM_INCLUDE=${PWD}/${LLVM_BASENAME}-install/include/c++/v1
LLVM_LIBPATH=${PWD}/${LLVM_BASENAME}-install/lib

if [[ -d "${LLVM_BASENAME}-install" ]] ; then
  log "${LLVM_BASENAME} already installed."
else
  rm -Rf ${LLVM_BASENAME}-source ${LLVM_BASENAME}-build

  log "Retrieving libc++."

  git clone --depth=1 -b release_60  https://github.com/llvm-mirror/llvm.git ${LLVM_BASENAME}-source
  git clone --depth=1 -b release_60  https://github.com/llvm-mirror/libcxx.git ${LLVM_BASENAME}-source/projects/libcxx
  git clone --depth=1 -b release_60  https://github.com/llvm-mirror/libcxxabi.git ${LLVM_BASENAME}-source/projects/libcxxabi

  log "Compiling libc++."

  mkdir -p ${LLVM_BASENAME}-build

  pushd ${LLVM_BASENAME}-build >/dev/null

  cmake -G "Ninja" \
      -DLIBCXX_ENABLE_EXPERIMENTAL_LIBRARY=OFF \
      -DLIBCXX_INSTALL_EXPERIMENTAL_LIBRARY=OFF \
      -DLLVM_ENABLE_EH=OFF \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX="../${LLVM_BASENAME}-install" \
      ../${LLVM_BASENAME}-source

  ninja cxx

  ninja install-libcxx

  ninja install-libcxxabi

  popd >/dev/null

  rm -Rf ${LLVM_BASENAME}-source ${LLVM_BASENAME}-build

fi

unset LLVM_BASENAME

# ==============================================================================
# -- Get boost includes --------------------------------------------------------
# ==============================================================================

BOOST_VERSION=1.69.0
BOOST_BASENAME="boost-${BOOST_VERSION}"

BOOST_INCLUDE=${PWD}/${BOOST_BASENAME}-install/include
BOOST_LIBPATH=${PWD}/${BOOST_BASENAME}-install/lib

if [[ -d "${BOOST_BASENAME}-install" ]] ; then
  log "${BOOST_BASENAME} already installed."
else

  rm -Rf ${BOOST_BASENAME}-source

  log "Retrieving boost."
  wget "https://dl.bintray.com/boostorg/release/${BOOST_VERSION}/source/boost_${BOOST_VERSION//./_}.tar.gz"
  log "Extracting boost."
  tar -xzf ${BOOST_BASENAME//[-.]/_}.tar.gz
  mkdir -p ${BOOST_BASENAME}-install/include
  mv ${BOOST_BASENAME//[-.]/_} ${BOOST_BASENAME}-source

  pushd ${BOOST_BASENAME}-source >/dev/null

  BOOST_TOOLSET="clang-6.0"
  BOOST_CFLAGS="-fPIC -std=c++14 -DBOOST_ERROR_CODE_HEADER_ONLY"

  py2="/usr/bin/env python2"
  py2_root=`${py2} -c "import sys; print(sys.prefix)"`
  pyv=`$py2 -c "import sys;x='{v[0]}.{v[1]}'.format(v=list(sys.version_info[:2]));sys.stdout.write(x)";`
  ./bootstrap.sh \
      --with-toolset=clang \
      --prefix=../boost-install \
      --with-libraries=python,filesystem \
      --with-python=${py2} --with-python-root=${py2_root}

  if ${TRAVIS}
  then
    echo "using python : ${pyv} : ${py2_root}/bin/python2 ;" > ${HOME}/user-config.jam
  else
    echo "using python : ${pyv} : ${py2_root}/bin/python2 ;" > project-config.jam
  fi

  ./b2 toolset="${BOOST_TOOLSET}" cxxflags="${BOOST_CFLAGS}" --prefix="../${BOOST_BASENAME}-install" -j ${CARLA_BUILD_CONCURRENCY} stage release
  ./b2 toolset="${BOOST_TOOLSET}" cxxflags="${BOOST_CFLAGS}" --prefix="../${BOOST_BASENAME}-install" -j ${CARLA_BUILD_CONCURRENCY} install
  ./b2 toolset="${BOOST_TOOLSET}" cxxflags="${BOOST_CFLAGS}" --prefix="../${BOOST_BASENAME}-install" -j ${CARLA_BUILD_CONCURRENCY} --clean-all

  # Get rid of  python2 build artifacts completely & do a clean build for python3
  popd >/dev/null
  rm -Rf ${BOOST_BASENAME}-source
  tar -xzf ${BOOST_BASENAME//[-.]/_}.tar.gz
  mkdir -p ${BOOST_BASENAME}-install/include
  mv ${BOOST_BASENAME//[-.]/_} ${BOOST_BASENAME}-source
  pushd ${BOOST_BASENAME}-source >/dev/null

  py3="/usr/bin/env python3"
  py3_root=`${py3} -c "import sys; print(sys.prefix)"`
  pyv=`$py3 -c "import sys;x='{v[0]}.{v[1]}'.format(v=list(sys.version_info[:2]));sys.stdout.write(x)";`
  ./bootstrap.sh \
      --with-toolset=clang \
      --prefix=../boost-install \
      --with-libraries=python, filesystem \
      --with-python=${py3} --with-python-root=${py3_root}

  if ${TRAVIS}
  then
    echo "using python : ${pyv} : ${py3_root}/bin/python3 ;" > ${HOME}/user-config.jam
  else
    echo "using python : ${pyv} : ${py3_root}/bin/python3 ;" > project-config.jam
  fi

  ./b2 toolset="${BOOST_TOOLSET}" cxxflags="${BOOST_CFLAGS}" --prefix="../${BOOST_BASENAME}-install" --with-python include="/usr/include/python3.5m/" -j ${CARLA_BUILD_CONCURRENCY} stage release 
  ./b2 toolset="${BOOST_TOOLSET}" cxxflags="${BOOST_CFLAGS}" --prefix="../${BOOST_BASENAME}-install" --with-python include="/usr/include/python3.5m/" -j ${CARLA_BUILD_CONCURRENCY} install
  popd >/dev/null

  rm -Rf ${BOOST_BASENAME}-source
  rm ${BOOST_BASENAME//[-.]/_}.tar.gz

fi

unset BOOST_BASENAME

# ==============================================================================
# -- Get rpclib and compile it with libc++ and libstdc++ -----------------------
# ==============================================================================

RPCLIB_PATCH=v2.2.1_c1
RPCLIB_BASENAME=rpclib-${RPCLIB_PATCH}

RPCLIB_LIBCXX_INCLUDE=${PWD}/${RPCLIB_BASENAME}-libcxx-install/include
RPCLIB_LIBCXX_LIBPATH=${PWD}/${RPCLIB_BASENAME}-libcxx-install/lib
RPCLIB_LIBSTDCXX_INCLUDE=${PWD}/${RPCLIB_BASENAME}-libstdcxx-install/include
RPCLIB_LIBSTDCXX_LIBPATH=${PWD}/${RPCLIB_BASENAME}-libstdcxx-install/lib

if [[ -d "${RPCLIB_BASENAME}-libcxx-install" && -d "${RPCLIB_BASENAME}-libstdcxx-install" ]] ; then
  log "${RPCLIB_BASENAME} already installed."
else
  rm -Rf \
      ${RPCLIB_BASENAME}-source \
      ${RPCLIB_BASENAME}-libcxx-build ${RPCLIB_BASENAME}-libstdcxx-build \
      ${RPCLIB_BASENAME}-libcxx-install ${RPCLIB_BASENAME}-libstdcxx-install

  log "Retrieving rpclib."

  git clone -b ${RPCLIB_PATCH} https://github.com/carla-simulator/rpclib.git ${RPCLIB_BASENAME}-source

  log "Building rpclib with libc++."

  # rpclib does not use any cmake 3.9 feature.
  # As cmake 3.9 is not standard in Ubuntu 16.04, change cmake version to 3.5
  sed -i s/"3.9.0"/"3.5.0"/g ${RPCLIB_BASENAME}-source/CMakeLists.txt

  mkdir -p ${RPCLIB_BASENAME}-libcxx-build

  pushd ${RPCLIB_BASENAME}-libcxx-build >/dev/null

  cmake -G "Ninja" \
      -DCMAKE_CXX_FLAGS="-fPIC -std=c++14 -stdlib=libc++ -I${LLVM_INCLUDE} -Wl,-L${LLVM_LIBPATH} -DBOOST_NO_EXCEPTIONS -DASIO_NO_EXCEPTIONS" \
      -DCMAKE_INSTALL_PREFIX="../${RPCLIB_BASENAME}-libcxx-install" \
      ../${RPCLIB_BASENAME}-source

  ninja

  ninja install

  popd >/dev/null

  log "Building rpclib with libstdc++."

  mkdir -p ${RPCLIB_BASENAME}-libstdcxx-build

  pushd ${RPCLIB_BASENAME}-libstdcxx-build >/dev/null

  cmake -G "Ninja" \
      -DCMAKE_CXX_FLAGS="-fPIC -std=c++14" \
      -DCMAKE_INSTALL_PREFIX="../${RPCLIB_BASENAME}-libstdcxx-install" \
      ../${RPCLIB_BASENAME}-source

  ninja

  ninja install

  popd >/dev/null

  rm -Rf ${RPCLIB_BASENAME}-source ${RPCLIB_BASENAME}-libcxx-build ${RPCLIB_BASENAME}-libstdcxx-build

fi

unset RPCLIB_BASENAME

# ==============================================================================
# -- Get GTest and compile it with libc++ --------------------------------------
# ==============================================================================

GTEST_BASENAME=googletest-1.8.0-ex

GTEST_LIBCXX_INCLUDE=${PWD}/${GTEST_BASENAME}-libcxx-install/include
GTEST_LIBCXX_LIBPATH=${PWD}/${GTEST_BASENAME}-libcxx-install/lib
GTEST_LIBSTDCXX_INCLUDE=${PWD}/${GTEST_BASENAME}-libstdcxx-install/include
GTEST_LIBSTDCXX_LIBPATH=${PWD}/${GTEST_BASENAME}-libstdcxx-install/lib

if [[ -d "${GTEST_BASENAME}-libcxx-install" && -d "${GTEST_BASENAME}-libstdcxx-install" ]] ; then
  log "${GTEST_BASENAME} already installed."
else
  rm -Rf \
      ${GTEST_BASENAME}-source \
      ${GTEST_BASENAME}-libcxx-build ${GTEST_BASENAME}-libstdcxx-build \
      ${GTEST_BASENAME}-libcxx-install ${GTEST_BASENAME}-libstdcxx-install

  log "Retrieving Google Test."

  git clone --depth=1 -b release-1.8.0 https://github.com/google/googletest.git ${GTEST_BASENAME}-source

  log "Building Google Test with libc++."

  mkdir -p ${GTEST_BASENAME}-libcxx-build

  pushd ${GTEST_BASENAME}-libcxx-build >/dev/null

  cmake -G "Ninja" \
      -DCMAKE_CXX_FLAGS="-std=c++14 -stdlib=libc++ -I${LLVM_INCLUDE} -Wl,-L${LLVM_LIBPATH} -DBOOST_NO_EXCEPTIONS -fno-exceptions" \
      -DCMAKE_INSTALL_PREFIX="../${GTEST_BASENAME}-libcxx-install" \
      ../${GTEST_BASENAME}-source

  ninja

  ninja install

  popd >/dev/null

  log "Building Google Test with libstdc++."

  mkdir -p ${GTEST_BASENAME}-libstdcxx-build

  pushd ${GTEST_BASENAME}-libstdcxx-build >/dev/null

  cmake -G "Ninja" \
      -DCMAKE_CXX_FLAGS="-std=c++14" \
      -DCMAKE_INSTALL_PREFIX="../${GTEST_BASENAME}-libstdcxx-install" \
      ../${GTEST_BASENAME}-source

  ninja

  ninja install

  popd >/dev/null

  rm -Rf ${GTEST_BASENAME}-source ${GTEST_BASENAME}-libcxx-build ${GTEST_BASENAME}-libstdcxx-build

fi

unset GTEST_BASENAME

# ==============================================================================
# -- Generate CMake toolchains and config --------------------------------------
# ==============================================================================

log "Generating CMake configuration files."

# -- LIBSTDCPP_TOOLCHAIN_FILE --------------------------------------------------

cat >${LIBSTDCPP_TOOLCHAIN_FILE}.gen <<EOL
# Automatically generated by `basename "$0"`

set(CMAKE_C_COMPILER ${CC})
set(CMAKE_CXX_COMPILER ${CXX})

set(CMAKE_CXX_FLAGS "\${CMAKE_CXX_FLAGS} -std=c++14 -pthread -fPIC" CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS "\${CMAKE_CXX_FLAGS} -Werror -Wall -Wextra" CACHE STRING "" FORCE)

# @todo These flags need to be compatible with setup.py compilation.
set(CMAKE_CXX_FLAGS_RELEASE_CLIENT "\${CMAKE_CXX_FLAGS_RELEASE} -DNDEBUG -g -fwrapv -O2 -Wall -Wstrict-prototypes -fno-strict-aliasing -Wdate-time -D_FORTIFY_SOURCE=2 -g -fstack-protector-strong -Wformat -Werror=format-security -fPIC -std=c++14 -Wno-missing-braces -DBOOST_ERROR_CODE_HEADER_ONLY -DLIBCARLA_ENABLE_LIFETIME_PROFILER -DLIBCARLA_WITH_PYTHON_SUPPORT" CACHE STRING "" FORCE)
EOL

# -- LIBCPP_TOOLCHAIN_FILE -----------------------------------------------------

# We can reuse the previous toolchain.
cp ${LIBSTDCPP_TOOLCHAIN_FILE}.gen ${LIBCPP_TOOLCHAIN_FILE}.gen

cat >>${LIBCPP_TOOLCHAIN_FILE}.gen <<EOL

set(CMAKE_CXX_FLAGS "\${CMAKE_CXX_FLAGS} -stdlib=libc++" CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS "\${CMAKE_CXX_FLAGS} -I${LLVM_INCLUDE}" CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS "\${CMAKE_CXX_FLAGS} -fno-exceptions" CACHE STRING "" FORCE)
set(CMAKE_CXX_LINK_FLAGS "\${CMAKE_CXX_LINK_FLAGS} -L${LLVM_LIBPATH}" CACHE STRING "" FORCE)
set(CMAKE_CXX_LINK_FLAGS "\${CMAKE_CXX_LINK_FLAGS} -lc++ -lc++abi" CACHE STRING "" FORCE)
EOL

# -- CMAKE_CONFIG_FILE ---------------------------------------------------------

cat >${CMAKE_CONFIG_FILE}.gen <<EOL
# Automatically generated by `basename "$0"`

set(CARLA_VERSION $(get_carla_version))

add_definitions(-DBOOST_ERROR_CODE_HEADER_ONLY)

if (CMAKE_BUILD_TYPE STREQUAL "Server")
  add_definitions(-DASIO_NO_EXCEPTIONS)
  add_definitions(-DBOOST_NO_EXCEPTIONS)
  add_definitions(-DLIBCARLA_NO_EXCEPTIONS)
  add_definitions(-DPUGIXML_NO_EXCEPTIONS)
endif ()

# Uncomment to force support for an specific image format (require their
# respective libraries installed).
# add_definitions(-DLIBCARLA_IMAGE_WITH_PNG_SUPPORT)
# add_definitions(-DLIBCARLA_IMAGE_WITH_JPEG_SUPPORT)
# add_definitions(-DLIBCARLA_IMAGE_WITH_TIFF_SUPPORT)

set(BOOST_INCLUDE_PATH "${BOOST_INCLUDE}")

if (CMAKE_BUILD_TYPE STREQUAL "Server")
  # Here libraries linking libc++.
  set(LLVM_INCLUDE_PATH "${LLVM_INCLUDE}")
  set(LLVM_LIB_PATH "${LLVM_LIBPATH}")
  set(RPCLIB_INCLUDE_PATH "${RPCLIB_LIBCXX_INCLUDE}")
  set(RPCLIB_LIB_PATH "${RPCLIB_LIBCXX_LIBPATH}")
  set(GTEST_INCLUDE_PATH "${GTEST_LIBCXX_INCLUDE}")
  set(GTEST_LIB_PATH "${GTEST_LIBCXX_LIBPATH}")
elseif (CMAKE_BUILD_TYPE STREQUAL "Client")
  # Here libraries linking libstdc++.
  set(RPCLIB_INCLUDE_PATH "${RPCLIB_LIBSTDCXX_INCLUDE}")
  set(RPCLIB_LIB_PATH "${RPCLIB_LIBSTDCXX_LIBPATH}")
  set(GTEST_INCLUDE_PATH "${GTEST_LIBSTDCXX_INCLUDE}")
  set(GTEST_LIB_PATH "${GTEST_LIBSTDCXX_LIBPATH}")
  set(BOOST_LIB_PATH "${BOOST_LIBPATH}")
endif ()

EOL

if [ "${TRAVIS}" == "true" ] ; then
  log "Travis CI build detected: disabling PNG support."
  echo "add_definitions(-DLIBCARLA_IMAGE_WITH_PNG_SUPPORT=false)" >> ${CMAKE_CONFIG_FILE}.gen
else
  echo "add_definitions(-DLIBCARLA_IMAGE_WITH_PNG_SUPPORT=true)" >> ${CMAKE_CONFIG_FILE}.gen
fi

# -- Move files ----------------------------------------------------------------

move_if_changed "${LIBSTDCPP_TOOLCHAIN_FILE}.gen" "${LIBSTDCPP_TOOLCHAIN_FILE}"
move_if_changed "${LIBCPP_TOOLCHAIN_FILE}.gen" "${LIBCPP_TOOLCHAIN_FILE}"
move_if_changed "${CMAKE_CONFIG_FILE}.gen" "${CMAKE_CONFIG_FILE}"

# ==============================================================================
# -- ...and we are done --------------------------------------------------------
# ==============================================================================

popd >/dev/null

log "Success!"
