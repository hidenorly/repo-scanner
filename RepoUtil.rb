#!/usr/bin/env ruby

# Copyright 2022, 2023 hidenory
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "shellwords"
require_relative "ExecUtil"
require_relative "FileUtil"
require_relative "GitUtil"
require 'rexml/document'

class RepoUtil
	DEF_REPOPATH = "/.repo"

	DEF_MANIFESTPATH = "#{DEF_REPOPATH}/manifests"
	DEF_MANIFESTFILE = "manifest.xml"
	DEF_MANIFESTFILE2 = DEF_MANIFESTFILE
	DEF_MANIFESTFILE_DIRS = [
		"/.repo/",
		"/.repo/manifests/"
	]

	def self.isRepoDirectory?(basePath)
		return Dir.exist?(basePath + DEF_MANIFESTPATH)
	end

	def self.getAvailableManifestPath(basePath, manifestFilename)
		DEF_MANIFESTFILE_DIRS.each do |aDir|
			path = basePath + aDir.to_s + manifestFilename
			if FileTest.exist?(path) then
				return path
			end
		end
		return nil
	end

	def self.getPathesFromManifestSub(basePath, manifestFilename, pathGitPath, pathFilter, groupFilter)
		manifestPath = getAvailableManifestPath(basePath, manifestFilename)
		if manifestPath && FileTest.exist?(manifestPath) then
			doc = REXML::Document.new(open(manifestPath))
			doc.elements.each("manifest/include[@name]") do |anElement|
				getPathesFromManifestSub(basePath, anElement.attributes["name"], pathGitPath, pathFilter, groupFilter)
			end
			doc.elements.each("manifest/project[@path]") do |anElement|
				thePath = anElement.attributes["path"].to_s
				theGitPath = anElement.attributes["name"].to_s
				if pathFilter.empty? || ( !pathFilter.to_s.empty? && thePath.match( pathFilter.to_s ) ) then
					theGroups = anElement.attributes["groups"].to_s
					if theGroups.empty? || groupFilter.empty? || ( !groupFilter.to_s.empty? && theGroups.match( groupFilter.to_s ) ) then
						pathGitPath[thePath] = theGitPath
					end
				end
			end
		end
	end

	def self.getPathesFromManifest(basePath, pathFilter="", groupFilter="")
		pathGitPath = {}

		getPathesFromManifestSub(basePath, DEF_MANIFESTFILE, pathGitPath, pathFilter, groupFilter)

		pathes = []
		pathGitPath.keys.each do |aPath|
			pathes << "#{basePath}/#{aPath}"
		end

		return pathes, pathGitPath
	end


	def self.getGitPathesFromManifest(basePath, manifestFile=DEF_MANIFESTFILE2)
		pathGitPath = {}
		getPathesFromManifestSub(basePath, manifestFile, pathGitPath, "", "")

		return pathGitPath
	end

	def self.getFlatFilenameFromGitPath(path)
		return path.tr("/", "-")
	end

	def self.getMatchedGitRevisions(gitRevisions, gitPathFilter)
		result = []
		gitPathFilter = Regexp.new(gitPathFilter.to_s) if gitPathFilter && !gitPathFilter.kind_of?(Regexp)
		gitRevisions.each do |aGitRevision|
			result << aGitRevision if !gitPathFilter || aGitRevision[:git].match(gitPathFilter)
		end
		return result
	end

	def self.getMatchedGits(gits, gitPathFilter)
		result = {}
		gitPathFilter = Regexp.new(gitPathFilter.to_s) if gitPathFilter && !gitPathFilter.kind_of?(Regexp)
		gits.each do |gitPath, gitName|
			result[gitPath] = gitName if !gitPathFilter || gitPath.match(gitPathFilter)
		end
		return result
	end

	def self.getAndMatchedGits(a, b)
		result = {}
		a.each do |k, v|
			result[k] = v if b && b.has_key?(k)# && b[k]==v
		end
		return result
	end

	def self.getAndMatchedGitsRobust(a, b)
		result = {}
		result_missing = []
		a.each do |a_k, a_v|
			found = false
			if b && b.has_key?(a_k) then
				result[a_k] = a_k
				found = true
			else
				foundA = ""
				foundB = ""
				b.each do |b_k, b_v|
					if b_k.end_with?("/"+a_k) || a_k.end_with?("/"+b_k) then
						if (foundA.length==0 && foundB.length==0) || ( (foundA.length > a_k.length) || (foundB.length > b_k.length) ) then
							found = true
							foundA = a_k
							foundB = b_k
						end
					end
				end
				result[foundA] = foundB if found
			end
			result_missing << a_k if !found
		end
		return result, result_missing
	end

	def self.getRobustMatchedGitsWithFilter(srcRepo, dstRepo, manifestFile=DEF_MANIFESTFILE2, regexpFilter=nil)
		gitPaths = {}
		missingPaths = []

		if isRepoDirectory?(srcRepo) then
			srcGitPaths =  getGitPathesFromManifest(srcRepo, manifestFile)
			srcGitPaths = getMatchedGits(srcGitPaths, regexpFilter)

			if isRepoDirectory?(dstRepo) then
				dstGitPaths = getGitPathesFromManifest(dstRepo, manifestFile)
				dstGitPaths = getMatchedGits(dstGitPaths, regexpFilter)
				gitPaths, missingPaths = getAndMatchedGitsRobust(srcGitPaths, dstGitPaths)
			else
				gitPaths = srcGitPaths
			end
		end

		return gitPaths, missingPaths
	end

	def self.getMatchedGitsWithFilter(repoPath, manifestFile=DEF_MANIFESTFILE2, regexpFilter=nil)
		gitPaths = {}

		if isRepoDirectory?(repoPath) then
			gitPaths =  getGitPathesFromManifest(repoPath, manifestFile)
			gitPaths = getMatchedGits(gitPaths, regexpFilter)
		end

		return gitPaths
	end


	def self.getMatchedGitRevisionsWithGits(gitRevisions, filterGits)
		result = []
		gitRevisions.each do |aGitRevision|
			result << aGitRevision if filterGits.has_key?(aGitRevision[:git])
		end
		return result
	end

	def self.getMissingGits(target,base)
		result = {}
		target.each do |k, v|
			result[k] = v if base && (!base.has_key?(k))# || base[k]!=v)
		end
		return result
	end

	def self.switchBranch(repoPath, branch, url=nil)
		exec_cmd = "repo init "
		exec_cmd += "-u #{Shellwords.shellescape(url)} " if url
		exec_cmd += "-b #{Shellwords.shellescape(branch)}"
		ExecUtil.execCmd(exec_cmd, repoPath)
	end

	def self.sync(repoPath, force=false, numOfThread=nil)
		exec_cmd = "repo sync -j #{numOfThread ? numOfThread : TaskManagerAsync.getNumberOfProcessor()}"
		exec_cmd += " -f" if force
		ExecUtil.execCmd(exec_cmd, repoPath)
	end
end
