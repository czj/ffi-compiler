require 'fileutils'
require 'tmpdir'
require 'ffi-compiler/compile_task'

RSpec.describe FFI::Compiler::CompileTask do
  around do |example|
    Dir.mktmpdir('ffi-compiler-compile-task') do |dir|
      Dir.chdir(dir) do
        Rake.with_application do
          verbose, Rake::FileUtilsExt.verbose_flag = Rake::FileUtilsExt.verbose_flag, false
          clean, clobber = CLEAN.dup, CLOBBER.dup
          example.run
        ensure
          Rake::FileUtilsExt.verbose_flag = verbose
          CLEAN.replace(clean)
          CLOBBER.replace(clobber)
        end
      end
    end
  end

  it 'defines a valid HAVE_ macro for a header in a subdirectory' do
    FileUtils.mkdir_p('include/foo')
    File.write('include/foo/bar-baz.h', "#define BAR_BAZ 1\n")
    FileUtils.mkdir_p('ext')
    File.write('ext/foo.c', <<~C)
      #ifndef HAVE_FOO_BAR_BAZ_H
      #error "HAVE_FOO_BAR_BAZ_H is not defined"
      #endif
      int foo(void) { return 1; }
    C

    found = nil
    described_class.new('ext/foo') { |t| found = t.have_header?('foo/bar-baz.h', File.join(Dir.pwd, 'include')) }

    expect(found).to be(true)
    expect { Rake::Task[:default].invoke }.not_to raise_error
  end

  describe '#have_header?' do
    it 'compiles its probe with the task cflags and defines' do
      FileUtils.mkdir_p('include')
      File.write('include/probe.h', "#if !defined(PROBE_ENABLED) || !defined(PROBE_FLAG)\n#error \"probe macros are not defined\"\n#endif\n")

      found = configure do |t|
        t.cflags << '-DPROBE_FLAG'
        t.add_define('PROBE_ENABLED')
        t.have_header?('probe.h', File.join(Dir.pwd, 'include'))
      end

      expect(found).to be(true)
    end

    it 'finds a header that includes one from another known include path' do
      FileUtils.mkdir_p(%w[a b])
      File.write('a/top.h', "#include <base.h>\n")
      File.write('b/base.h', "#define BASE 1\n")

      found = configure do |t|
        t.add_include_path(File.join(Dir.pwd, 'b'))
        t.have_header?('top.h', File.join(Dir.pwd, 'a'))
      end

      expect(found).to be(true)
    end

    it 'does not find a missing header' do
      expect(configure { |t| t.have_header?('ffi_compiler_missing.h', Dir.pwd) }).to be(false)
    end
  end

  def configure
    result = nil
    described_class.new('ext/foo') { |t| result = yield t }
    result
  end
end
