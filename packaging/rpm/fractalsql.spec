%global moddir   /usr/lib/redis/modules
%global confdir  /etc/redis/modules-available

Name:           redis-fractalsql
Version:        1.0.0
Release:        1%{?dist}
Summary:        Stochastic Fractal Search module for Redis

License:        MIT
URL:            https://github.com/FractalSQLabs/redis-fractalsql
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  gcc, make, curl, git
Requires:       redis

BuildArch:      %{_arch}

%description
redis-fractalsql is a native C module for Redis 6.2 / 7.0 / 7.2 / 7.4
(ABI-compatible with 8.x) that exposes a FRACTAL.SEARCH command
backed by a LuaJIT-compiled Stochastic Fractal Search optimizer.
The command is declared readonly / fast / allow-stale.

LuaJIT is statically linked into the module; the only runtime
dependency is glibc.

Enable by adding to redis.conf:

    loadmodule /usr/lib/redis/modules/fractalsql.so

An example config snippet is installed at
/etc/redis/modules-available/fractalsql.conf.

%prep
%setup -q

%build
# The per-arch .so is produced out-of-band by build.sh on a Docker
# builder; this spec stages the prebuilt artifact.
test -f dist/%{_arch}/fractalsql.so

%install
# Claim %dir ownership of the Redis modules directory since no base
# package owns it on stock RHEL-family installs.
install -d -m 0755 %{buildroot}%{moddir}
install -d -m 0755 %{buildroot}%{confdir}

install -Dm0755 dist/%{_arch}/fractalsql.so \
    %{buildroot}%{moddir}/fractalsql.so
install -Dm0644 scripts/load_module.conf \
    %{buildroot}%{confdir}/fractalsql.conf
install -Dm0644 LICENSE \
    %{buildroot}%{_docdir}/%{name}/LICENSE
install -Dm0644 LICENSE-THIRD-PARTY \
    %{buildroot}%{_docdir}/%{name}/LICENSE-THIRD-PARTY

%files
%license LICENSE
%dir %{moddir}
%dir %{confdir}
%{moddir}/fractalsql.so
%{_docdir}/%{name}/LICENSE
%{_docdir}/%{name}/LICENSE-THIRD-PARTY
%config(noreplace) %{confdir}/fractalsql.conf

%post
cat <<'EOF'

redis-fractalsql installed.

The module is at:
    /usr/lib/redis/modules/fractalsql.so

Enable it by adding this to redis.conf:

    loadmodule /usr/lib/redis/modules/fractalsql.so

Or include the shipped snippet:

    include /etc/redis/modules-available/fractalsql.conf

Then restart the server:

    sudo systemctl restart redis

Verify:

    redis-cli MODULE LIST
    redis-cli FRACTALSQL.EDITION
    redis-cli FRACTALSQL.VERSION
    redis-cli COMMAND INFO FRACTAL.SEARCH

EOF

%changelog
* Sat Apr 18 2026 FractalSQLabs <ops@fractalsqlabs.io> - 1.0.0-1
- Initial Factory-standardized release for Redis 6.2 / 7.0 / 7.2 /
  7.4 (ABI-compatible with 8.x). Static LuaJIT, zero-dependency
  posture. Verified on AMD64 and ARM64.
