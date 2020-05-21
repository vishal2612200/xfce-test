FROM ubuntu:19.10
MAINTAINER Florian Schüller <florian.schueller@gmail.com>

ENV DEBIAN_FRONTEND noninteractive
ENV DISPLAY ${DISPLAY:-:1}

# Test specific
# python-wheel is a missing dependency from behave
# psmisc for "killall"
RUN apt-get update \
 && apt-get -y --no-install-recommends install apt-utils psmisc ffmpeg x11-utils libxrandr-dev \
 && apt-get -y --no-install-recommends install dirmngr git python-ldtp ldtp python-pip python-wheel python3-dogtail python-psutil python-setuptools vim sudo gdb valgrind tmuxinator tmux ltrace \
 && rm -rf /var/lib/apt/lists/*

RUN /usr/bin/pip install behave

# Enable source repositories
RUN sed -Ei 's/^# deb-src /deb-src /' /etc/apt/sources.list

# Xfce specific build dependencies and default panel plugins
RUN apt-get update \
 && apt-get -y --no-install-recommends install gnome-themes-standard libglib2.0-bin build-essential libgtk-3-dev gtk-doc-tools libgtk2.0-dev libx11-dev libglib2.0-dev libwnck-3-dev intltool libdbus-glib-1-dev liburi-perl x11-xserver-utils libvte-2.91-dev dbus-x11 strace libgl1-mesa-dev adwaita-icon-theme libwnck-dev adwaita-icon-theme-full cmake libsoup2.4-dev libpcre2-dev exo-utils libgtksourceview-3.0-dev libtag1-dev \
&& apt-get -y --no-install-recommends install libgstreamer1.0-0 gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav gstreamer1.0-doc gstreamer1.0-tools gstreamer1.0-x gstreamer1.0-alsa gstreamer1.0-gl gstreamer1.0-gtk3 gstreamer1.0-qt5 gstreamer1.0-pulseaudio \
 && apt-get -y --no-install-recommends build-dep xfce4-panel thunar xfce4-settings xfce4-session xfdesktop4 xfwm4 xfce4-appfinder tumbler xfce4-terminal xfce4-clipman-plugin xfce4-screenshooter \
 && apt-get -y --no-install-recommends install xfce4-pulseaudio-plugin xfce4-statusnotifier-plugin \
 && apt-get -y --no-install-recommends install python-distutils-extra \
 && apt-get -y --no-install-recommends install libxss-dev \
 && apt-get -y --no-install-recommends install libindicator3-dev \
 && apt-get -y --no-install-recommends install libxmu-dev \
 && apt-get -y --no-install-recommends install libburn-dev libisofs-dev \
 && apt-get -y --no-install-recommends install libpulse-dev libkeybinder-3.0-dev \
 && apt-get -y --no-install-recommends install libmpd-dev valac gobject-introspection libgirepository1.0-dev \
 && apt-get -y --no-install-recommends install libvala-0.44-dev librsvg2-dev libtagc0-dev \
 && apt-get -y --no-install-recommends install libdbusmenu-gtk3-dev \
 && apt-get -y --no-install-recommends install libgtop2-dev \
 && apt-get -y remove libxfce4ui-1-0 libxfce4ui-2-0 \
 && rm -rf /var/lib/apt/lists/*

#needed for LDTP and friends
RUN /usr/bin/dbus-run-session /usr/bin/gsettings set org.gnome.desktop.interface toolkit-accessibility true

# Create the directory for version_info.txt
RUN useradd -ms /bin/bash xfce-test_user

RUN adduser xfce-test_user sudo
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Install _all_ languages for testing
RUN apt-get update \
 && apt-get -y --no-install-recommends install transifex-client xautomation $(apt-cache search language-pack|grep -oP "^language-pack-...?(?= )") \
 && rm -rf /var/lib/apt/lists/*

RUN pip install opencv-python google-api-python-client oauth2client

RUN cp /usr/share/i18n/locales/en_GB /usr/share/i18n/locales/automate
RUN sed -i -E "s/Language: en/Language: automate/" /usr/share/i18n/locales/automate
RUN sed -i -E "s/lang_lib +\"eng\"/lang_lib    \"automate\"/" /usr/share/i18n/locales/automate
RUN sed -i -E "s/lang_name +\"English\"/lang_name     \"Automate\"/" /usr/share/i18n/locales/automate
RUN bash -c "cd /usr/share/i18n/locales;localedef -i automate -f UTF-8 automate.UTF-8 -c -v || echo Ignoring warnings..." \
 && echo "automate UTF-8" > /var/lib/locales/supported.d/automate \
 && locale-gen automate
RUN dpkg-reconfigure fontconfig

# Line used to invalidate all git clones
ARG PARALLEL_BUILDS=0
ENV PARALLEL_BUILDS=$PARALLEL_BUILDS
ARG DOWNLOAD_DATE=give_me_a_date
ENV DOWNLOAD_DATE=$DOWNLOAD_DATE
RUN echo "Newly cloning all repos as date-flag changed to ${DOWNLOAD_DATE}"
ARG AUTOGEN_OPTIONS="--disable-debug --enable-maintainer-mode --host=x86_64-linux-gnu \
                    --build=x86_64-linux-gnu --prefix=/usr --libdir=/usr/lib/x86_64-linux-gnu \
                    --libexecdir=/usr/lib/x86_64-linux-gnu --sysconfdir=/etc --localstatedir=/var --enable-gtk3 --enable-gtk-doc\
                    --enable-vala=yes --enable-introspection=yes"
ENV AUTOGEN_OPTIONS $AUTOGEN_OPTIONS

USER xfce-test_user
ENV HOME /home/xfce-test_user

# Group all repos here
RUN sudo mkdir /git && sudo chown xfce-test_user /git

# Rather use my patched version
RUN cd git \
 && git clone https://github.com/schuellerf/ldtp2.git \
 && cd ldtp2 \
 && python setup.py build \
 && sudo python setup.py install

COPY --chown=xfce-test_user container_scripts /container_scripts
RUN chmod a+x /container_scripts/*.sh /container_scripts/*.py

RUN /container_scripts/build_all.sh

# only available after building exo:
RUN sudo apt-get update \
 && sudo apt-get -y --no-install-recommends install exo-utils \
 && sudo rm -rf /var/lib/apt/lists/*

COPY --chown=xfce-test_user behave /behave_tests
RUN sudo mkdir /data && sudo chown xfce-test_user /data

COPY --chown=xfce-test_user xfce-test /
RUN chmod a+x /xfce-test
COPY .tmuxinator /home/xfce-test_user/.tmuxinator

RUN mkdir -p ~xfce-test_user/Desktop
RUN ln -s /container_scripts ~xfce-test_user/Desktop/container_scripts
RUN ln -s ~xfce-test_user/version_info.txt ~xfce-test_user/Desktop

#RUN echo 'if [[ $- =~ "i" ]]; then echo -n "This container includes:\n"; cat ~xfce-test_user/version_info.txt; fi' >> ~xfce-test_user/.bashrc

WORKDIR /data
CMD [ "/container_scripts/entrypoint.sh" ]
