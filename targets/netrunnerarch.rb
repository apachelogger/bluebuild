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

class Chroot
    attr_reader :path
    attr_reader :mounted_paths

    def initialize(path)
        @path = path
        @mounted_paths = []
    end

    def setup()
        mount('-o bind /proc', '/proc/')
        mount('-o bind /sys', '/sys/')
        mount('-o bind /dev', '/dev/')
        mount('-p', '/dev/pts')
        mount('-t devpts devpts', '/dev/pts')

        system("cp '/etc/resolv.conf' '#{path}/etc/'") if File.exist?('/etc/resolv.conf')

        # Make sure we overwrite systemd-nspawn to establish an upstart compatible
        # chroot execution. This is necessary because the manjaro specific build
        # tools internally will try to nspawn which will fail on systems <=14.04
        # as there is no systemd available to manage the nspawning.
        FileUtils.cp("#{File.dirname __FILE__}/netrunnerarch/systemd-nspawn",
                     "#{path}/usr/local/bin/",
                     :verbose=>true)
        FileUtils.cp("#{File.dirname __FILE__}/netrunnerarch/systemd-nspawn",
                     "#{path}/usr/bin/",
                     :verbose=>true)
        FileUtils.cp("#{File.dirname __FILE__}/netrunnerarch/systemd-nspawn",
                     "#{path}/usr/sbin/",
                     :verbose=>true)

        # Worksaround a Debian compat issue.
        FileUtils.mkpath("#{path}/run/shm")
    end

    def bind(bind_path)
        mount("-o bind #{bind_path}", bind_path)
    end

    def run(cmd)
        return system("chroot #{path} #{cmd}")
    end

    def teardown()
        @mounted_paths = mounted_paths.reverse.drop_while do |mounted_path|
            puts ":::unmount(#{path}#{mounted_path})"
            system("umount -v -f -l #{path}#{mounted_path}")
        end
        p @mounted_paths
    end

private
    def mount(options, target_path)
        puts ":::mount(#{options}, #{target_path})"
        system("mkdir -p '#{path}#{target_path}'")
        system("mount #{options} #{path}#{target_path}")
        @mounted_paths << target_path
    end
end

class Netrunnerarch < Builder
    attr_reader :chroot_path
    attr_reader :repo_path

private
# TODO: move to chroot class
# TODO: what to do with chroot_path, should that maybe simply be set in the Chroot? currently that is NRA exclusive
    def create_chroot()
        @chroot_path = "#{Blue::Config[:chroot_basepath]}/netrunnerarch"
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
        chroot = Chroot.new(chroot_path)
        chroot.setup()
        chroot.bind(build_path)

        # Remove SUDO variables from the envrionment as manjarobuild tries to use it for
        # chroot creation, making it fail if the user doesn't exist.
        ENV.delete('SUDO_USER')
        ENV.delete('SUDO_UID')
        chroot.run("sh -c 'cd #{build_path} && { stable-x86_64-build; stable-i686-build; }'")
        ##

        chroot.teardown()
    end

    def repo_add(pkgtar)
    end

    def build_internal()
        Dir.chdir(build_path) do
            Dir.glob("#{source.path}/netrunnerarch/*").each do |file|
                FileUtils.cp_r(file, build_path, :verbose=>true)
                create_chroot()
                build_in_chroot()

                # NOTE: the tar.xs are now supposed to be in build_path
                pkgarches = []
                File.readlines('PKGBUILD').each do |line|
                    if line.start_with?('arch=')
                        # Sub away the arch=() part.
                        line.gsub!(/arch=\((.*)\)/, '\1')
                        # What remains may be a space separate list of ' quoted
                        # arch identifiers.
                        # Split by separator, remove the quotes and convert to
                        # symbol.
                        line.split(' ').each do |arch|
                            pkgarches << arch.gsub("'", '').to_sym
                        end
                    end
                end

                pkgtars = Dir.glob('*.pkg.tar.xz')

                p pkgarches
                p pkgtars
                # Check that there is a package for all defined architectures.
                pkgarches.each do |pkgarch|
                    found = false
                    pkgtars.each do |pkgtar|
                        found = true if (pkgarch == File.basename(pkgtar, '.pkg.tar.xz').split('-').last.to_sym)
                        break if found
                    end
                    next if found
                    # No match found, we are missing a build, oh my.
                    # FIXME: return error etc.
                    # TODO: should we return at all? maybe publish what we have instead?
                    puts "netrunnerach pkgbuild for #{pkgarch} failed apparently"
                    return
                end

                @repo_path = "#{Blue::Config[:repo_basepath]}/netrunnerarch"
                FileUtils.mkpath(repo_path)
                FileUtils.cp(pkgtars, repo_path, :verbose => true)
                Dir.chdir(repo_path) do
                    chroot = Chroot.new(chroot_path)
                    chroot.setup()
                    chroot.bind(repo_path)
                    pkgtars.each do |pkgtar|
                        # TODO: param for repo?
                        chroot.run("sh -c 'cd #{repo_path} && repo-add bluebuild.db.tar.gz #{pkgtar}'")
                    end
                    chroot.teardown()
                end
                # TODO: extract logs and whatnot for publication
                # NOTE: packages are not signed intentionally apparently
            end
        end
    end
end

# TODO: !!!!!!!!!!!!!!!!!!!
# /usr/share/devtools/pacman-default.conf
# before the core entry
# [blueshell]
# SigLevel = Optional TrustAll
# Server=http://arch.netrunner-os.com/$arch

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
