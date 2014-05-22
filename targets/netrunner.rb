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

class Netrunner < Builder
private
    def debian_version()
        Dir.chdir(build_path) do
            FileUtils.rm_rf('debian')
            FileUtils.cp_r(source.path + '/netrunner', 'debian')
            %x[dpkg-parsechangelog].split("\n").each do |line|
                next unless line.start_with?('Version: ')
                version = line
                version.gsub!(/^Version: /, '') # Strip Version: prefix
                version.gsub!(/^[0-9]*:/, '') # Strip epoch
                version.gsub!(/-[^-]*$$/, '') # Strip the revision
                return version
            end
        end
    end

    def create_orig_tar()
        Dir.chdir(build_path) do
            %x[tar -cf #{source.name}.tar git_data]
            %x[xz -9 #{source.name}.tar]
            %x[ln -s #{source.name}.tar.xz #{source.name}_#{debian_version(source)}.orig.tar.xz]
        end
    end

    def build_internal()
        Dir.chdir(build_path) do
            p source.meta_data
            # FIXME: the checkout dir...
            %x[git clone #{source.meta_data[:source]} git_data]
            # FIXME: the netrunner dir construction is slightly out of place and repated all over the place...
            debian = source.path + '/netrunner'
            if File.exist?("#{debian}/source/format")
                create_orig_tar(source) unless File.read("#{debian}/source/format").include?('(native)')
            end
            Dir.chdir('git_data') do
                # FIXME: new path construction, very shitty
                # FIXME: should check whether netrunner exists and debian exists and then leave debian or replace or ororor
                FileUtils.rm_rf('debian')
                FileUtils.cp_r(source.path + "/netrunner", "debian", :verbose => true)
                %x[dpkg-buildpackage -S -us -uc]
            end
            puts "dput *.dsc"
        end
    end
end