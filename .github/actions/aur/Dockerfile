FROM docker.io/library/archlinux:base-devel@sha256:9414f5b766a34ebd769608b9ec80e1b4bfd7ea5e86dd49cae06ae308ad6c4221

RUN pacman -Syu --needed --noconfirm pacman-contrib namcap git sudo && \
  useradd -m builder && \
  echo 'builder ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

WORKDIR /home/builder
USER builder

# Install yay
RUN git clone https://aur.archlinux.org/yay-bin.git
WORKDIR /home/builder/yay-bin
RUN makepkg -si --noconfirm

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]