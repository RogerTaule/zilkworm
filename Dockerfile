## This is to be built locally on an environment already working with the build

FROM ubuntu:25.04
RUN apt update 
RUN apt install -y --no-install-recommends ca-certificates curl gpg

# Install Docker for Docker-in-Docker call
# Add Docker's official GPG key:
 RUN apt update
 RUN apt install ca-certificates curl
 RUN install -m 0755 -d /etc/apt/keyrings
 RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
 RUN chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
RUN echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
   tee /etc/apt/sources.list.d/docker.list > /dev/null
RUN apt update

RUN apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Install NVIDIA Container Runtime for child docker to run proving on GPU
RUN curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

RUN apt update
RUN apt install -y \
      nvidia-container-toolkit \
      nvidia-container-toolkit-base \
      libnvidia-container-tools \
      libnvidia-container1

COPY ./target/release/z6m_prover /usr/bin/z6m_prover
COPY ./target/elf-compilation/riscv32im-succinct-zkvm-elf/release/z6m_guest /usr/local/bin/z6m_guest

ENTRYPOINT ["/usr/bin/z6m_prover"]
CMD ["--help"]