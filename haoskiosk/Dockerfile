################################################################################
# Add-on: HAOS Kiosk Display (haoskiosk)
# File: Dockerfile
# Base: Debian Bookworm (glibc) — required for Chromium WebGL/WASM stability
# Copyright Jeff Kosowsky / Welizard Chromium fork
################################################################################

ARG BUILD_FROM
FROM $BUILD_FROM

ARG BUILD_VERSION
ENV ADDON_VERSION=${BUILD_VERSION}

#===============================================================================
##### Add Debian Bookworm backports for Mesa 25.0 (Intel N150 / ADL-N 0x46d4 support)
RUN echo "deb http://deb.debian.org/debian bookworm-backports main" \
      >> /etc/apt/sources.list.d/backports.list

##### Install X, Browser and all necessary dependencies
##### Mesa/GL packages from backports for Intel N150 iris driver support
RUN apt-get update && apt-get install -y --no-install-recommends \
## Xserver and graphics
     xserver-xorg-core \
     xserver-xorg-video-all \
   && apt-get install -t bookworm-backports -y --no-install-recommends \
     libgl1-mesa-dri \
     libegl-mesa0 \
     libgles2 \
     libgl1 \
     mesa-vulkan-drivers \
     libvulkan1 \
   && apt-get install -y --no-install-recommends \
     libdrm2 \
### X utils
     xdotool \
     xinput \
     x11-xserver-utils \
     libxkbcommon0 \
     x11-xkb-utils \
### Input, udev
     xserver-xorg-input-libinput \
     xserver-xorg-input-evdev \
     libinput10 \
     libinput-tools \
     udev \
     libevdev2 \
     evtest \
### Window, mouse, keyboard management
     openbox \
     onboard \
     unclutter-xfixes \
     fonts-dejavu-core \
     fonts-noto-color-emoji \
### Linux utils
     bash \
     util-linux \
     bsdmainutils \
     dconf-cli \
     libglib2.0-bin \
     patch \
     scrot \
     procps \
### Python libraries
     python3-pip \
     python3-xlib \
### Sound
     pulseaudio-utils \
### VNC (for debugging)
     x11vnc \
## Browsers
     chromium \
     luakit \
   && rm -rf /var/lib/apt/lists/*

#===============================================================================

##### Set the display variable
ENV DISPLAY=:0

##### Build tty0_override.so — LD_PRELOAD library to fake /dev/tty0 VT access
# Needed because HAOS containers block /dev/tty0 access on Debian
COPY tty0_override.c /tmp/
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev \
    && gcc -shared -fPIC -o /usr/lib/tty0_override.so /tmp/tty0_override.c -ldl \
    && rm /tmp/tty0_override.c \
    && apt-get remove -y gcc libc6-dev \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

##### Copy over 'xorg.conf.default' and lua 'userconf.lua' file
COPY xorg.conf.default /etc/X11/
COPY userconf.lua /root/.config/luakit/
COPY translations/*.yaml /translations/

COPY run.sh touch_mapping.sh /
RUN chmod a+x /run.sh

COPY mouse_touch_inputs.py gesture_commands.json /
COPY rest_server.py /
COPY browser_ctl.py target_url.py chromium_watchdog.py /
RUN pip install --no-cache-dir --break-system-packages aiohttp

#### Patches
# Need to patch 'unique_instance.lua' so that new instance urls overwrite active url rather than add new tab
COPY unique_instance.patch /usr/share/luakit/lib/
RUN patch -p2 /usr/share/luakit/lib/unique_instance.lua < /usr/share/luakit/lib/unique_instance.patch || true

CMD ["/run.sh"]
