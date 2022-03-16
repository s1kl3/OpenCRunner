# Docker image based on Debian Stretch with LLVM, Clang and the OpenCRun runtime
# for OpenCL. It also downloads some benchmark packages.
FROM debian:stretch
MAINTAINER Giulio Sichel <Giulio.Sichel@gmail.com>

# Installation folder.
ARG PREFIX=/home/docker/local

# The number of CPU cores used in the build process is set by default to the
# result of the nproc command.
ARG CPU_NUM=`nproc`

# Choose an LLVM/Clang release (llvm_v3.5|llvm_v3.7|llvm_v6|dev). The "dev"
# development release uses the latest snapshots from the repositories and
# thus it might fail building. By default the stable release for LLVM v.6 is
# built.
ARG BUILD_RELEASE=llvm_v6

# Build type (Debug|Release|RelWithDebInfo|MinSizeRel)
ARG BUILD_TYPE=RelWithDebInfo

# Execute as "root"
USER root

# Install dependencie, useful tools and create the unpriviledged user "docker".
CMD ["echo","Download and installation of software dependencies"]
RUN apt-get -y update \
&& apt-get install -y apt-utils build-essential autoconf automake cmake ninja-build git \
&& apt-get install -y python hwloc libhwloc-dev \
&& apt-get install -y libgl1-mesa-dev libglew2.0 libglew-dev freeglut3 freeglut3-dev \
&& apt-get install -y bash-completion time unzip ranger htop vim gnuplot ncdu

# Switch to the "docker" user to execute commands.
CMD ["echo","Switching to an unpriviledged user"]
RUN useradd -m -s /bin/bash -c "Docker User" docker 
USER docker
WORKDIR /home/docker

# Create the "src" directory within the user home folder and
# copy the OpenCRunner shell script to handle the building process.
CMD ["echo","Building and installing LLVM/Clang/OpenCRun"]
RUN mkdir src
COPY OpenCRunner.sh src/
RUN cd src \
    && ./OpenCRunner.sh build --type $BUILD_TYPE \
    # To specify a custom CPU number which is not the total number of logical cores.
    # && --cpu $CPU_NUM
    # To specify a custom destination folder ($HOME/local by default).
    # && --prefix $PREFIX \
    # To specify the desired release (LLVM/Clang v.6 by default).
    # && --$BUILD_RELEASE \
    # To specify the build type (release with debugging symbols by default).
    # && --type $BUILD_TYPE \ 
    && echo -e "\n\nexport PATH=$HOME/local/bin:$PATH" >> ~/.bashrc \
    && echo -e "\n\nexport LD_LIBRARY_PATH=$HOME/local/lib:$LD_LIBRARY_PATH" >> ~/.bashrc

CMD ["echo","Image created"]
