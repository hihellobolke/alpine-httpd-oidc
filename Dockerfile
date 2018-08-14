FROM alpine:3.7
# Apache installation is from: 
#    https://github.com/docker-library/httpd/blob/38842a5d4cdd44ff4888e8540c0da99009790d01/2.4/alpine/Dockerfile




RUN set -x \
	&& addgroup -g 82 -S www-data \
	&& adduser -u 82 -D -S -G www-data www-data
    # 82 is the standard uid/gid for "www-data" in Alpine
    # http://git.alpinelinux.org/cgit/aports/tree/main/apache2/apache2.pre-install?h=v3.3.2
    # http://git.alpinelinux.org/cgit/aports/tree/main/lighttpd/lighttpd.pre-install?h=v3.3.2
    # http://git.alpinelinux.org/cgit/aports/tree/main/nginx-initscripts/nginx-initscripts.pre-install?h=v3.3.2




# I generally use /app or /opt, 
#   but I will follow the standard
ENV INSTALL_BASE="/usr/local"
ENV HTTPD_PREFIX="${INSTALL_BASE}/apache2"
ENV HTTPD_DEP_PREFIX="${INSTALL_BASE}"
ENV PATH="$HTTPD_PREFIX/bin:$PATH"
ENV JANSSON_VERSION 2.11
ENV CJOSE_VERSION 0.6.1
ENV OIDC_VERSION 2.3.7
ENV OIDC_URL="https://github.com/zmartzone/mod_auth_openidc/archive/v${OIDC_VERSION}.zip"
ENV OIDC_URL_DEV="https://github.com/zmartzone/mod_auth_openidc/archive/master.zip"
# ENV OIDC_URL_DEV="https://github.com/hihellobolke/mod_auth_openidc/archive/master.zip"
ENV HTTPD_VERSION 2.4.34
ENV HTTPD_SHA256 fa53c95631febb08a9de41fd2864cfff815cf62d9306723ab0d4b8d7aa1638f0
    
# https://httpd.apache.org/security/vulnerabilities_24.html
ENV HTTPD_PATCHES=""

ENV APACHE_DIST_URLS \
    # https://issues.apache.org/jira/browse/INFRA-8753?focusedCommentId=14735394#comment-14735394
	https://www.apache.org/dyn/closer.cgi?action=download&filename= \
    # if the version is outdated (or we're grabbing the .asc file), we might have to pull from the dist/archive :/
	https://www-us.apache.org/dist/ \
	https://www.apache.org/dist/ \
	https://archive.apache.org/dist/

# Save deps in the file
ENV INSTALL_DEPS="${INSTALL_BASE}/install.deps"




# Set workdir and install dependencies
WORKDIR $HTTPD_PREFIX
RUN set -eux; \
    \
    mkdir -p "$HTTPD_PREFIX" && chown www-data:www-data "$HTTPD_PREFIX"; \
	\
	runDeps=' \
		apr-dev \
		apr-util-dev \
		apr-util-ldap \
		perl \
	'; \
	apk add --no-cache --virtual .build-deps \
		$runDeps \
		ca-certificates \
		coreutils \
		dpkg-dev dpkg \
		gcc \
		gnupg \
		libc-dev \
		# mod_session_crypto \
		libressl \
		libressl-dev \
		# mod_proxy_html mod_xml2enc \
		libxml2-dev \
		# mod_lua \
		lua-dev \
		make \
		# mod_http2 \
		nghttp2-dev \
		pcre-dev \
		tar \
		# mod_deflate \
		zlib-dev \
        \
        \
        # mod_auth_oidc \
        git \
        curl \
        curl-dev \
        hiredis \
        hiredis-dev \
        automake \
        autoconf;


# jansson dependency for oidc
RUN set -x \
    && export PKG_CONFIG_PATH=/usr/lib/pkgconfig:/app/local/lib/pkgconfig \
    && mkdir -p /tmp/src /tmp/download \
    && /usr/bin/wget -nv -O /tmp/download/jansson.tar.gz http://www.digip.org/jansson/releases/jansson-${JANSSON_VERSION}.tar.gz \
        && tar -zxf /tmp/download/jansson.tar.gz -C /tmp/src \
            && cd /tmp/src/jansson* && ./configure \
                --prefix="${HTTPD_DEP_PREFIX}" \
            && make > mk.log \
            && make install \
        && cd / \
        && /bin/rm -rf /tmp/download/jansson.tar.gz /tmp/src/jansson*


# cjose dependency for oidc
RUN set -x \
    && /usr/bin/wget -nv -O /tmp/download/cjose.tar.gz https://github.com/cisco/cjose/archive/${CJOSE_VERSION}.tar.gz \
    && tar -zxf /tmp/download/cjose.tar.gz -C /tmp/src \
        && cd /tmp/src/cjose* && ./configure \
            --prefix="${HTTPD_DEP_PREFIX}" \
            --with-jansson="${HTTPD_DEP_PREFIX}" \
        && make > mk.log \
        && make install \
    && cd / \
    && /bin/rm -rf /tmp/download/cjose.tar.gz /tmp/src/cjose*


# Compile apache now
RUN set -eux; \
    \
	ddist() { \
		local f="$1"; shift; \
		local distFile="$1"; shift; \
		local success=; \
		local distUrl=; \
		for distUrl in $APACHE_DIST_URLS; do \
			if wget -O "$f" "$distUrl$distFile" && [ -s "$f" ]; then \
				success=1; \
				break; \
			fi; \
		done; \
		[ -n "$success" ]; \
	}; \
	\
	ddist 'httpd.tar.bz2' "httpd/httpd-$HTTPD_VERSION.tar.bz2"; \
	echo "$HTTPD_SHA256 *httpd.tar.bz2" | sha256sum -c -; \
	\
    # see https://httpd.apache.org/download.cgi#verify
	ddist 'httpd.tar.bz2.asc' "httpd/httpd-$HTTPD_VERSION.tar.bz2.asc"; \
	export GNUPGHOME="$(mktemp -d)"; \
	for key in \
        # gpg: key 791485A8: public key "Jim Jagielski (Release Signing Key) <jim@apache.org>" imported
		A93D62ECC3C8EA12DB220EC934EA76E6791485A8 \
        # gpg: key 995E35221AD84DFF: public key "Daniel Ruggeri (http://home.apache.org/~druggeri/) <druggeri@apache.org>" imported
		B9E8213AEFB861AF35A41F2C995E35221AD84DFF \
	; do \
		gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$key"; \
	done; \
	gpg --batch --verify httpd.tar.bz2.asc httpd.tar.bz2; \
	command -v gpgconf && gpgconf --kill all || :; \
	rm -rf "$GNUPGHOME" httpd.tar.bz2.asc; \
	\
	mkdir -p src; \
	tar -xf httpd.tar.bz2 -C src --strip-components=1; \
	rm httpd.tar.bz2; \
	cd src; \
	\
	patches() { \
		while [ "$#" -gt 0 ]; do \
			local patchFile="$1"; shift; \
			local patchSha256="$1"; shift; \
			ddist "$patchFile" "httpd/patches/apply_to_$HTTPD_VERSION/$patchFile"; \
			echo "$patchSha256 *$patchFile" | sha256sum -c -; \
			patch -p0 < "$patchFile"; \
			rm -f "$patchFile"; \
		done; \
	}; \
	patches $HTTPD_PATCHES; \
	\
	gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
	./configure \
		--build="$gnuArch" \
		--prefix="$HTTPD_PREFIX" \
		--enable-mods-shared=reallyall \
		--enable-mpms-shared=all \
	; \
	make -j "$(nproc)"; \
	make install; \
	\
	cd ..; \
	rm -r src man manual; \
	\
	sed -ri \
		-e 's!^(\s*CustomLog)\s+\S+!\1 /proc/self/fd/1!g' \
		-e 's!^(\s*ErrorLog)\s+\S+!\1 /proc/self/fd/2!g' \
		"$HTTPD_PREFIX/conf/httpd.conf"; 



# mod_auth_oidc
RUN set -x \
    && export PKG_CONFIG_PATH=/usr/lib/pkgconfig:/app/local/lib/pkgconfig \
    && /usr/bin/wget -nv -O /tmp/download/mod_auth_openidc.zip $OIDC_URL_DEV \
    && cd /tmp/src && unzip /tmp/download/mod_auth_openidc.zip \
    && cd /tmp/src/mod_* \
        && ./autogen.sh \
        && ./configure --with-apxs2=${HTTPD_PREFIX}/bin/apxs \
        && make  \
        && make install \
    && cd / \
    && /bin/rm -rf /tmp/download/mod_auth_openidc.zip /tmp/src/mod_auth_openidc*



RUN set -x \
    && runDeps="$runDeps $( \
        scanelf --needed --nobanner --format '%n#p' --recursive ${INSTALL_BASE} \
            | tr ',' '\n' \
            | sort -u \
            | awk 'system("[ -e /app/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
            | grep -v libcjose \
            | grep -v libjansson \
        )" \
    && echo $runDeps > $INSTALL_DEPS \
    && apk add --virtual .httpd-rundeps $runDeps \
	&& apk del .build-deps


COPY httpd-foreground /usr/local/bin/


EXPOSE 80
CMD ["httpd-foreground"]
