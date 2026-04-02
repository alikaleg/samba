FROM quay.io/fedora/fedora:41 AS bootstaraped-fedora-samba

# pass in with --build-arg while build
ARG SHA1SUM
RUN [ -n $SHA1SUM ] && echo $SHA1SUM > /sha1sum.txt

ADD bootstrap/generated-dists/fedora41/*.sh /tmp/
# need root permission, do it before USER samba
RUN /tmp/bootstrap.sh && /tmp/locale.sh

# if ld.gold exists, force link it to ld
RUN set -x; ! LD_GOLD=$(which ld.gold) || { LD=$(which ld) && ln -sf $LD_GOLD $LD && test -x $LD && echo "$LD is now $LD_GOLD"; }
# if ld.mold exists, force link it to ld (prefer mold over gold! ;-)
RUN set -x; ! LD_MOLD=$(which ld.mold) || { LD=$(which ld) && ln -sf $LD_MOLD $LD && test -x $LD && echo "$LD is now $LD_MOLD"; }

# make test can not work with root, so we have to create a new user
RUN useradd -m -U -s /bin/bash samba && \
    mkdir -p /etc/sudoers.d && \
    echo "samba ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/samba

USER samba
WORKDIR /home/samba
# samba tests rely on this
ENV USER=samba LC_ALL=en_US.utf8 LANG=en_US.utf8 LANGUAGE=en_US

FROM bootstaraped-fedora-samba AS build-samba
RUN mkdir -p build
COPY . .
RUN sudo ./configure \
    --enable-cephfs \
    --without-gpgme \
    --without-ads \
    --disable-cups \
    --without-pam \
    --disable-glusterfs \
    --without-ad-dc \
    --without-ldap \
    --without-ldb-lmdb \
    --disable-iprint \
    --without-sendfile-support \
    --disable-avahi \
    --disable-spotlight \
    --disable-wsp \
    --without-systemd \
    --without-lttng \
    --with-shared-modules=vfs_nfs4acl_xattr
RUN sudo make -j 14
RUN sudo make install -j 14

FROM quay.io/fedora/fedora:41
RUN dnf install --assumeyes jansson libbsd libicu-devel libcephfs2
COPY --from=build-samba /usr/local/samba /usr/local/samba
RUN mkdir -p /var/log/samba/cores
RUN chmod 700 /var/log/samba/cores
CMD ["/usr/local/samba/sbin/smbd", "--foreground", "--no-process-group"]
