FROM docker.io/library/archlinux:base-devel@sha256:7c81df532d6307c5bccb3d2561c90bfc981e6c4384d2a61c9e49b7f2d8aa27c0

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