FROM djavanargent/arch-base:latest
MAINTAINER djavanargent

# additional files
##################

# add install bash script
ADD setup/root/*.sh /root/

# add bash script to run openvpn
ADD apps/root/*.sh /root/

# add bash script to run privoxy
ADD apps/nobody/*.sh /home/nobody/

# add pia certificates and sample openvpn.ovpn file
ADD config/pia/default/* /home/nobody/certs/default/
ADD config/pia/strong/* /home/nobody/certs/strong/

# install app
#############

# run bash script to update base image, set locale, install supervisor and cleanup
RUN chmod +x /root/*.sh /home/nobody/*.sh && \
	/bin/bash /root/install.sh

# docker settings
#################

# expose port for privoxy
EXPOSE 8118
