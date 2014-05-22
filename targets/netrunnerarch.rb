#--
# Copyright (C) 2014 Harald Sitter <sitter@kde.org>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of
# the License or (at your option) version 3 or any later version
# accepted by the membership of KDE e.V. (or its successor approved
# by the membership of KDE e.V.), which shall act as a proxy
# defined in Section 14 of version 3 of the license.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#++

require 'fileutils'

require_relative 'builder'

class Netrunnerarch < Builder
    attr_reader :chroot_path

private
    def setup_chroot()
        # FIXME: how is this supposed to work with x64 vs x86
        @chroot_path = "#{Blue::Config[:chroot_basepath]}/netrunnerarch"
        p @chroot_path
        return if File.exist?(chroot_path)

        env = {
            'CHROOT_DIR' => chroot_path,
            'ADDITIONAL_PACKAGES' => 'manjaroiso git base base-devel ruby'
        }
        # FIXME: we possibly should branch that out somewhere for reuse
        if system(env, "sudo -E #{File.dirname __FILE__}/netrunnerarch/manjaro-bootstrap.sh")
            # In Debian, /dev/shm points to /run/shm. However, in the Arch-based
            # chroot, /run/shm does not exist and the link is broken.
            FileUtils.mkpath("#{chroot_path}/run/shm")
        else # fail
            FileUtils.rm_rf(chroot_path)
        end
    end

    def build_in_chroot()
        bind = build_path

        # FIXME: need i686 and x86_64 ... or we somehow get the thing to
        #        adjust chroots, which seems a bit dirty
        system("mount -o bind /proc '#{chroot_path}/proc/'")
        system("mount -o bind /sys '#{chroot_path}/sys/'")
        system("mount -o bind /dev '#{chroot_path}/dev/'")
        system("mkdir -p '#{chroot_path}/dev/pts'")
        system("mount -t devpts devpts '#{chroot_path}/dev/pts/'")

        system("cp '/etc/resolv.conf' '#{chroot_path}/etc/'") if File.exist?('/etc/resolv.conf')

        # TODO: need to bind build path I guess, then run stable-build on that path
        system("mkdir -p '#{chroot_path}/#{bind}'")
        system("mount -o bind #{bind} '#{chroot_path}/#{bind}'")

        ##
        # FIXME: needs cmd
        # TODO: need to copy fake systemd-nspawn
        FileUtils.cp("#{File.dirname __FILE__}/netrunnerarch/systemd-nspawn", "#{chroot_path}/usr/local/bin/", :verbose=>true)
#         FileUtils.cp("#{File.dirname __FILE__}/netrunnerarch/systemd-nspawn", "#{chroot_path}/usr/bin/", :verbose=>true)
#         FileUtils.cp("#{File.dirname __FILE__}/netrunnerarch/systemd-nspawn", "#{chroot_path}/usr/sbin/", :verbose=>true)
        p bind
        ENV.delete('SUDO_USER')
        ENV.delete('SUDO_UID')
        system("chroot #{chroot_path}  sh -c 'cd #{bind} && { stable-x86_64-build; stable-i686-build; }'")
        ##

        system("umount '#{chroot_path}/#{bind}'")

        system("umount '#{chroot_path}/dev/pts'")
        system("umount '#{chroot_path}/dev'")
        system("umount '#{chroot_path}/sys'")
        system("umount '#{chroot_path}/proc'")
    end

    def build_internal()
        Dir.chdir(build_path) do
            Dir.glob("#{source.path}/netrunnerarch/*").each do |file|
                FileUtils.cp_r(file, build_path, :verbose=>true)
                setup_chroot()
                build_in_chroot()
            end
        end
    end
end

# 1) Install Netrunnerarch in a VM
# 2) Install the base-devel package
# 3) Grab PKGBUILD github repo
# 4) cd PKGBUILD/PKGNAME
#   4 a) Modify if required
#   4 b) Run updpkgsums to update pkg hashes
#   4 c) Commit changes
# 5) sudo stable-x86_64-build / stable-i686-build
# 6) copy over *pkg.tar.xz to server
# 7) Drink some Coke Zero

#https://github.com/manjaro/devtools/blob/master/manjarobuild.in
#https://github.com/edge226/Manjaro-bootstrap/blob/master/manjaro-bootstrap.sh