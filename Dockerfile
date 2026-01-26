FROM ubuntu:jammy

######### Customize Container Here ###########

RUN apt update
RUN apt -y upgrade
RUN apt -y install openvpn
RUN apt -y install unzip
RUN apt-get install -y wget
RUN rm -rf /var/lib/apt/lists/*

RUN apt update && \
    DEBIAN_FRONTEND=noninteractive apt install -y cinnamon locales sudo

RUN apt update && \
    DEBIAN_FRONTEND=noninteractive apt install -y xrdp tigervnc-standalone-server && \
    adduser xrdp ssl-cert && \
    locale-gen en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8    

ARG USER=sgoncalves
ARG PASS=123456

RUN useradd -m $USER -p $(openssl passwd $PASS) && \
    usermod -aG sudo $USER && \
    groupadd power && \
    usermod -aG power $USER && \
    chsh -s /bin/bash $USER


RUN echo "#!/bin/sh\n\
    export XDG_SESSION_DESKTOP=cinnamon\n\
    export XDG_SESSION_TYPE=x11\n\
    export XDG_CURRENT_DESKTOP=X-Cinnamon\n\
    export XDG_CONFIG_DIRS=/etc/xdg/xdg-cinnamon:/etc/xdg" > /env && chmod 555 /env

RUN echo "#!/bin/sh\n\
    . /env\n\
    exec dbus-run-session -- cinnamon-session" > /xstartup && chmod +x /xstartup

RUN mkdir /home/$USER/.vnc && \
    echo $PASS | vncpasswd -f > /home/$USER/.vnc/passwd && \
    chmod 0600 /home/$USER/.vnc/passwd && \
    chown -R $USER:$USER /home/$USER/.vnc

RUN cp -f /xstartup /etc/xrdp/startwm.sh && \
    cp -f /xstartup /home/$USER/.vnc/xstartup

RUN echo "#!/bin/sh\n\
    sudo -u $USER -g $USER -- vncserver -rfbport 5902 -geometry 1920x1080 -depth 24 -verbose -localhost no -autokill no" > /startvnc && chmod +x /startvnc

EXPOSE 3389
EXPOSE 5902

# Change Background to sth cool
ADD docs/images/mr-robot-wallpaper.png  /usr/share/extra/backgrounds/bg_default.png

# Install Starship
RUN wget https://starship.rs/install.sh
RUN chmod +x install.sh
RUN ./install.sh -y

# Add Starship to bashrc
RUN echo 'eval "$(starship init bash)"' >> .bashrc

# Add Starship Theme
ADD scripts/config/starship.toml .config/starship.toml

# Install Hack Nerd Font
RUN wget https://github.com/ryanoasis/nerd-fonts/releases/download/v2.1.0/Hack.zip
RUN unzip Hack.zip -d /usr/local/share/fonts

######### End Customizations ###########

#CMD service dbus start; /usr/lib/systemd/systemd-logind & service xrdp start; /startvnc; bash
#SHELL ["/bin/bash", "-c"]
#CMD ["service dbus start", "/usr/lib/systemd/systemd-logind", "service xrdp start", "/startvnc", "bash"]

ENTRYPOINT service dbus start; /usr/lib/systemd/systemd-logind & service xrdp start; /startvnc; bash


######### HOW TO USE ###########

## Run command line: 
## docker build -f Dockerfile -t docker-cinnamon .
## docker run -p 3390:3389 -it docker-cinnamon /bin/bash
## Then just use your favorite RDP client to connect to localhost:3390
