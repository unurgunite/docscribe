# frozen_string_literal: true

RSpec.describe Docscribe::InlineRewriter::DocBlock do
  let(:tag_order) { %w[note private protected param option raise return] }

  describe '.sort' do
    subject(:out) do
      described_class.render(
        described_class.sort(entries, tag_order: sort_order)
      )
    end

    describe 'sorts contiguous tags by configured order' do
      let(:entries) do
        described_class.parse([
                                "# @return [Object]\n",
                                "# @param [Object] foo\n"
                              ], tag_order: tag_order)
      end
      let(:sort_order) { %w[param return] }

      it { is_expected.to eq(["# @param [Object] foo\n", "# @return [Object]\n"]) }
    end

    describe 'does not sort across blank comment separators' do
      let(:lines) do
        [
          "# @return [Object]\n",
          "#\n",
          "# @param [Object] foo\n"
        ]
      end
      let(:entries) { described_class.parse(lines, tag_order: tag_order) }
      let(:sort_order) { %w[param return] }

      it { is_expected.to eq(lines) }
    end

    describe 'does not sort across plain comment text' do
      let(:lines) do
        [
          "# @return [Object]\n",
          "# some stupid comment\n",
          "# @param [Object] foo\n"
        ]
      end
      let(:entries) { described_class.parse(lines, tag_order: tag_order) }
      let(:sort_order) { %w[param return] }

      it { is_expected.to eq(lines) }
    end

    describe 'moves multiline tag entries as a unit' do
      let(:entries) do
        described_class.parse([
                                "# @return [Object]\n",
                                "# @param [Object] foo Some param with very long string\n",
                                "#                                          which we split in two lines\n"
                              ], tag_order: tag_order)
      end
      let(:sort_order) { %w[param return] }

      it {
        expect(out).to eq(["# @param [Object] foo Some param with very long string\n",
                           "#                                          which we split in two lines\n",
                           "# @return [Object]\n"])
      }
    end

    describe 'keeps @option tags attached to their owning @param' do
      let(:entries) do
        described_class.parse([
                                "# @return [Object]\n",
                                "# @param [Hash] opts the options to create a message with.\n",
                                "# @option opts [String] :subject The subject\n",
                                "# @option opts [String] :from ('nobody') From address\n",
                                "# @param [String] name the name\n"
                              ], tag_order: tag_order)
      end
      let(:sort_order) { %w[param option return] }

      it {
        expect(out).to eq(["# @param [Hash] opts the options to create a message with.\n",
                           "# @option opts [String] :subject The subject\n",
                           "# @option opts [String] :from ('nobody') From address\n",
                           "# @param [String] name the name\n",
                           "# @return [Object]\n"])
      }
    end

    describe 'supports name-first @param syntax' do
      let(:entries) do
        described_class.parse([
                                "# @return [Object]\n",
                                "# @param foo [Object] Generated param description.\n"
                              ], tag_order: tag_order)
      end
      let(:sort_order) { %w[param return] }

      it { is_expected.to eq(["# @param foo [Object] Generated param description.\n", "# @return [Object]\n"]) }
    end
  end

  describe '.merge' do
    subject(:merge_out) do
      described_class.merge(
        [
          "# Existing docs\n",
          "# @return [Object]\n",
          "# @param [Object] foo blah-blah\n"
        ],
        missing_lines: [
          "# @raise [ArgumentError]\n"
        ],
        sort_tags: true,
        tag_order: %w[param raise return]
      )
    end

    it {
      expect(merge_out).to eq(["# Existing docs\n", "# @param [Object] foo blah-blah\n",
                               "# @raise [ArgumentError]\n",
                               "# @return [Object]\n"])
    }
  end
end
