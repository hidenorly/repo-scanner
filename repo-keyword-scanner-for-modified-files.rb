#!/usr/bin/ruby

# Copyright 2023 hidenorly
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

require 'optparse'
require_relative 'ExecUtil'
require_relative 'TaskManager'
require_relative "RepoUtil"
require_relative "Reporter"


class ExecKeywordScan < TaskAsync
	def initialize(resultCollector, srcPath, dstPath, relativePath, options)
		super("ExecKeywordScan::#{srcPath} #{dstPath} #{relativePath}")
		@resultCollector = resultCollector
		@srcPath = srcPath
		@srcGitOpt = options[:srcGitOpt]
		@dstPath = dstPath
		@dstGitOpt = options[:dstGitOpt]
		@relativePath = relativePath
		@keyword = options[:keyword]
		@options = options
		@isMissing = options[:detect] == "missing"
	end

	DEF_EXEC_FILE_COUNTS = 30

	def _getModifiedFiles(srcPath, dstPath, dstGitOpt, enableNewFile=true)
		actualModifiedFiles = []
		dstModifiedFiles = []
		isDiffChecked = false

		if File.directory?(dstPath) then
			#Avoid git in git situation then do following instead of diff -r -x .git in the git
			_dstModifiedFiles = GitUtil.getFilesWithGitOpts(dstPath, dstGitOpt)
			_dstModifiedFiles.each do |aTargetFile|
				dstModifiedFiles << aTargetFile if !FileClassifier.isBinaryFile( aTargetFile )
			end

			puts "#{dstPath}:dstModifiedFiles=#{dstModifiedFiles}" if @options[:verbose]

			dstModifiedFiles.each do |aTargeFile|
				targetSrcFile = srcPath + "/" + aTargeFile
				targetDstFile = dstPath + "/" + aTargeFile
				if File.exist?(targetDstFile) then
					exec_cmd = "diff -U 0"
					exec_cmd = exec_cmd + " -N" if enableNewFile
					exec_cmd = exec_cmd + " #{Shellwords.shellescape(targetSrcFile)} #{Shellwords.shellescape(targetDstFile)}"
					exec_cmd = exec_cmd + " 2>/dev/null"
					exec_cmd = exec_cmd + " | grep -Ev \'^(\\+\\+\\+|\\-\\-\\-)\' | grep \'^\\+\' | wc -l"
					result = ExecUtil.getExecResultEachLine(exec_cmd, dstPath, false)
					puts "#{exec_cmd}=#{result}" if @options[:verbose]
					isDiffChecked = true
					if result[0].to_i!=0 then
						# found diffed file!
						actualModifiedFiles << aTargeFile
					end
				end
			end
		end

		return isDiffChecked ? actualModifiedFiles : dstModifiedFiles
	end

	def _execKeywordSearch(dstPath, targetFiles, keyword)
		found = []
		missed = []
		cnt = 0
		_actualModifiedFiles=""
		_candidates = []
		targetFiles.each do |aFile|
			theFile = Shellwords.shellescape(aFile)
			cnt = cnt + 1
			if cnt >= DEF_EXEC_FILE_COUNTS || aFile == targetFiles.last then
				if File.file?(dstPath+"/"+aFile) && !_actualModifiedFiles.include?(theFile) then
					_actualModifiedFiles = _actualModifiedFiles + (!_actualModifiedFiles.empty? ? " " : "") + theFile
					_candidates << aFile
				end
				if !_actualModifiedFiles.empty? then
					exec_cmd = "grep -Ec \'#{@keyword}\' #{_actualModifiedFiles}"
					if _candidates.length == 1 then
						exec_cmd += " | grep #{@isMissing ? "" : "-v "}\'0\'"
					else
						exec_cmd += " | grep #{@isMissing ? "" : "-v "}\':0\'"
					end
					puts "#{exec_cmd}" if @options[:verbose]
					_tmp = ExecUtil.getExecResultEachLine(exec_cmd, dstPath, false)
					_tmp.each do |aResult|
						pos = aResult.index(":")
						aResult = pos ? aResult.slice(0, pos) : _candidates[0]
						aResult.strip!
						missed << aResult
					end
				end
				found.concat( _candidates - missed )
				_candidates = []
				_actualModifiedFiles=""
				cnt = 0
			else
				if File.file?(dstPath+"/"+aFile) then
					_actualModifiedFiles = _actualModifiedFiles + (!_actualModifiedFiles.empty? ? " " : "") + theFile
					_candidates << aFile
				end
			end
		end
		return found, missed
	end


	def execute
		patchDir = RepoUtil.getFlatFilenameFromGitPath(@relativePath)

		srcPath = @srcPath.to_s+"/"+@relativePath
		dstPath = @dstPath.to_s+"/"+@relativePath

		actualModifiedFiles = _getModifiedFiles(srcPath, dstPath, @dstGitOpt )
		puts "#{dstPath}:actualModifiedFiles=#{actualModifiedFiles}" if @options[:verbose]

		found, missed = _execKeywordSearch(dstPath, actualModifiedFiles, @keyword)

		puts "#{dstPath}:found=#{found}" if @options[:verbose]
		puts "#{dstPath}:missed=#{missed}" if @options[:verbose]

		result = ""
		targets = missed #@isMissing ? missed : found
		targets.each do |aFile|
			result = result + (!result.empty? ? ":" : "") + aFile.to_s
		end
		@resultCollector.onResult( @relativePath, result ) if !result.empty?

		_doneTask()
	end
end


#---- main --------------------------
options = {
	:manifestFile => RepoUtil::DEF_MANIFESTFILE,
	:logDirectory => Dir.pwd,
	:disableLog => false,
	:verbose => false,
	:srcDir => nil,
	:srcGitOpt => "",
	:dstDir => ".",
	:dstGitOpt => "",
	:gitPath => nil,
	:prefix => "",
	:mode=>"source&target",
	:keyword => "Copyright",
	:detect => "missing",
	:reportOutPath => nil,
	:numOfThreads => TaskManagerAsync.getNumberOfProcessor()
}

reporter = CsvReporter


opt_parser = OptionParser.new do |opts|
	opts.banner = "Usage: -s sourceRepoDir -t targetRepoDir"
	opts.on("-k", "--keyword=", "Specify keyword (default:#{options[:keyword]})") do |keyword|
		options[:keyword] = keyword
	end

	opts.on("-d", "--detect=", "Specify keyword detection mode:detected or missing (default:#{options[:detect]})") do |detect|
		options[:detect] = detect
	end

	opts.on("-s", "--source=", "Specify source repo dir. if you want to exec as delta/new files") do |src|
		options[:srcDir] = src
	end

	opts.on("", "--sourceGitOpt=", "Specify gitOpt for source repo dir.") do |srcGitOpt|
		options[:srcGitOpt] = srcGitOpt
	end

	opts.on("-t", "--target=", "Specify target repo dir.") do |dst|
		options[:dstDir] = dst
	end

	opts.on("", "--targetGitOpt=", "Specify gitOpt for target repo dir.") do |dstGitOpt|
		options[:dstGitOpt] = dstGitOpt
	end

	opts.on("-m", "--mode=", "Specify mode \"source&target\" or \"target-source\" (default:#{options[:mode]})") do |mode|
		options[:mode] = mode
	end

	opts.on("-g", "--gitPath=", "Specify target git path (regexp) if you want to limit to execute the git only") do |gitPath|
		options[:gitPath] = gitPath
	end

	opts.on("-p", "--prefix=", "Specify prefix if necessary to add for the path") do |prefix|
		options[:prefix] = prefix
	end

	opts.on("-o", "--output=", "Specify report file path") do |reportOutPath|
		options[:reportOutPath] = reportOutPath
	end

	opts.on("-f", "--reportFormat=", "Specify markdown or csv") do |reportFormat|
		reportFormat.downcase!
		reporter = MarkdownReporter if reportFormat=="markdown"
	end

	opts.on("", "--manifestFile=", "Specify manifest file (default:#{options[:manifestFile]})") do |manifestFile|
		options[:manifestFile] = manifestFile
	end

	opts.on("-j", "--numOfThreads=", "Specify number of threads (default:#{options[:numOfThreads]})") do |numOfThreads|
		options[:numOfThreads] = numOfThreads
	end

	opts.on("-v", "--verbose", "Enable verbose status output (default:#{options[:verbose]})") do
		options[:verbose] = true
	end

end.parse!

options[:srcDir] = File.expand_path(options[:srcDir]) if options[:srcDir]
options[:dstDir] = File.expand_path(options[:dstDir])

# common
resultCollector = ResultCollectorHash.new()
taskMan = ThreadPool.new( options[:numOfThreads].to_i )

if ( options[:srcDir] && !RepoUtil.isRepoDirectory?(options[:srcDir]) ) then
	puts "-s #{options[:srcDir]} is not repo directory"
	exit(-1)
end

if ( !RepoUtil.isRepoDirectory?(options[:dstDir]) ) then
	puts "-t #{options[:dstDir]} is not repo directory"
	exit(-1)
end

targetGits = RepoUtil.getMatchedGitsWithFilter( options[:dstDir], options[:manifestFile], options[:gitPath] )
if options[:srcDir] && options[:dstDir] then
	matched, missed = RepoUtil.getRobustMatchedGitsWithFilter( options[:srcDir], options[:dstDir], options[:manifestFile], options[:gitPath])
	case options[:mode].downcase
	when "source&target" then
		targetGits = matched
	when "target-source" then
		targetGitKeys = targetGits.keys - matched.keys
		_tmp = {}
		targetGitKeys.each do |theKey|
			_tmp[theKey] = targetGits[theKey]
		end
		targetGits = _tmp
	end
end

targetGits.each do | path, gitPath |
	puts path if options[:verbose]
	taskMan.addTask( ExecKeywordScan.new(resultCollector, options[:srcDir], options[:dstDir], path, options) )
end

taskMan.executeAll()
taskMan.finalize()

results = resultCollector.getResult()
results = results.sort

reporter = reporter.new( options[:reportOutPath] )

if reporter.class == MarkdownReporter then
	reporter.println( "| path | filename |" )
	reporter.println( "| :--- | :--- |" )
	results.each do | path, result |
		_result = result.split(":")
		result = {}
		result[path] = _result
		reporter.report( result )
	end
else
	results.each do | path, result |
		reporter.println( "#{options[:prefix]}#{path},#{result}" )
	end
end

reporter.close()
