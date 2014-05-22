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
require_relative '../config'

class Builder
    # Path to use for building (e.g. imagine /tmp/)
    attr_accessor :parent_build_path
    # The actual source specific build path
    attr_reader :build_path
    # The source to build
    attr_reader :source

    def initialize(source, distro_working_dir_name = self.class.name.downcase)
        @parent_build_path = Blue::Config[:build_basepath]
        @build_path = "#{parent_build_path}/#{distro_working_dir_name}/#{source.name}"
        @source = source
        p self
    end

    def build()
        FileUtils.rm_rf(build_path)
        FileUtils.mkpath(build_path)
        Dir.chdir(build_path) { build_internal() }
    end

    def build_internal()
        raise "Pure virtual"
    end
end
