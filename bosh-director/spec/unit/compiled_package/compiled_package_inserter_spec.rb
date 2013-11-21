require 'spec_helper'
require 'bosh/director/compiled_package/compiled_package_inserter'
require 'fileutils'
require 'fakefs/spec_helpers'

module Bosh::Director::CompiledPackage
  describe CompiledPackageInserter do
    let(:blobstore_client) { instance_double('Bosh::Blobstore::BaseClient') }
    subject(:inserter) { described_class.new(blobstore_client) }

    let!(:release) { Bosh::Director::Models::Release.make }
    let!(:release_version) { Bosh::Director::Models::ReleaseVersion.make(release: release) }
    let(:package) do
      Bosh::Director::Models::Package.make(
        fingerprint: 'fingerprint1',
        dependency_set_json: '["dep1", "dep2"]',
        release: release
      )
    end

    let!(:stemcell) { Bosh::Director::Models::Stemcell.make(sha1: 'stemcell-sha1') }
    let!(:dep1) { Bosh::Director::Models::Package.make(name: 'dep1', release: release) }
    let!(:dep2) { Bosh::Director::Models::Package.make(name: 'dep2', release: release) }

    before do
      package.add_release_version(release_version)
      dep1.add_release_version(release_version)
      dep2.add_release_version(release_version)
    end

    include FakeFS::SpecHelpers
    before { FileUtils.touch('/path_to_extracted_blob') }

    context 'when the compiled package has not been inserted before' do
      let(:compiled_package) do
        instance_double(
          'Bosh::Director::CompiledPackage::CompiledPackage',
          package_name: 'package1',
          package_fingerprint: 'fingerprint1',
          sha1: 'compiled-package-sha1',
          stemcell_sha1: 'stemcell-sha1',
          blobstore_id: 'blobstore_id1',
          blob_path: '/path_to_extracted_blob',
        )
      end

      it 'creates a blob in the blobstore' do
        f = double('blob file')
        File.stub(:open).with('/path_to_extracted_blob').and_yield(f)
        blobstore_client.should_receive(:create).with(f, 'blobstore_id1')

        inserter.insert(compiled_package, release_version)
      end

      it 'inserts a compiled package in the database' do
        blobstore_client.stub(:create)
        inserter.insert(compiled_package, release_version)

        # pull the last package added to the DB in order to exercise save()
        retrieved_package = Bosh::Director::Models::CompiledPackage.order(:id).last

        expect(retrieved_package.blobstore_id).to eq('blobstore_id1')
        expect(retrieved_package.package_id).to eq(package.id)
        expect(retrieved_package.stemcell_id).to eq(stemcell.id)
        expect(retrieved_package.sha1).to eq('compiled-package-sha1')
        expect(retrieved_package.dependency_key).to eq(Yajl::Encoder.encode([[dep1.name, dep1.version], [dep2.name, dep2.version]]))
      end

      it 'records the blob in database only after creating the blob' do
        blobstore_client.should_receive(:create).ordered

        # we need to stub out .create because we do not use randomly generated blob on import yet
        # transitioning to that will also fix story #61162324
        Bosh::Director::Models::CompiledPackage.should_receive(:create).ordered

        inserter.insert(compiled_package, release_version)
      end
    end

    context 'when the compiled package has been inserted before' do
      before do
        Bosh::Director::Models::CompiledPackage.make(
          package: package,
          stemcell: stemcell,
          dependency_key: Yajl::Encoder.encode([[dep1.name, dep1.version], [dep2.name, dep2.version]]),
        )
      end

      let(:compiled_package) do
        instance_double(
          'Bosh::Director::CompiledPackage::CompiledPackage',
          package_name: 'package1',
          package_fingerprint: 'fingerprint1',
          sha1: 'compiled-package-sha1',
          stemcell_sha1: 'stemcell-sha1',
          blobstore_id: 'blobstore_id1',
          blob_path: '/path_to_extracted_blob',
        )
      end

      it 'does not insert a compiled package into the database' do
        expect {
          inserter.insert(compiled_package, release_version)
        }.not_to change { Bosh::Director::Models::CompiledPackage.count }
      end

      it 'does not create another blob for the compiled package' do
        expect(blobstore_client).not_to receive(:create)
        inserter.insert(compiled_package, release_version)
      end
    end
  end
end
