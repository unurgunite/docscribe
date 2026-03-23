# frozen_string_literal: true

RSpec.describe Docscribe::InlineRewriter::DocBlock do
  let(:tag_order) { %w[note private protected param option raise return] }

  describe '.sort' do
    it 'sorts contiguous tags by configured order' do
      entries = described_class.parse([
                                        "# @return [Object]\n",
                                        "# @param [Object] foo\n"
                                      ], tag_order: tag_order)

      out = described_class.render(
        described_class.sort(entries, tag_order: %w[param return])
      )

      expect(out).to eq([
                          "# @param [Object] foo\n",
                          "# @return [Object]\n"
                        ])
    end

    it 'does not sort across blank comment separators' do
      lines = [
        "# @return [Object]\n",
        "#\n",
        "# @param [Object] foo\n"
      ]

      entries = described_class.parse(lines, tag_order: tag_order)
      out = described_class.render(
        described_class.sort(entries, tag_order: %w[param return])
      )

      expect(out).to eq(lines)
    end

    it 'does not sort across plain comment text' do
      lines = [
        "# @return [Object]\n",
        "# some stupid comment\n",
        "# @param [Object] foo\n"
      ]

      entries = described_class.parse(lines, tag_order: tag_order)
      out = described_class.render(
        described_class.sort(entries, tag_order: %w[param return])
      )

      expect(out).to eq(lines)
    end

    it 'moves multiline tag entries as a unit' do
      entries = described_class.parse([
                                        "# @return [Object]\n",
                                        "# @param [Object] foo Some param with very long string\n",
                                        "#                                          which we split in two lines\n"
                                      ], tag_order: tag_order)

      out = described_class.render(
        described_class.sort(entries, tag_order: %w[param return])
      )

      expect(out).to eq([
                          "# @param [Object] foo Some param with very long string\n",
                          "#                                          which we split in two lines\n",
                          "# @return [Object]\n"
                        ])
    end

    it 'keeps @option tags attached to their owning @param' do
      entries = described_class.parse([
                                        "# @return [Object]\n",
                                        "# @param [Hash] opts the options to create a message with.\n",
                                        "# @option opts [String] :subject The subject\n",
                                        "# @option opts [String] :from ('nobody') From address\n",
                                        "# @param [String] name the name\n"
                                      ], tag_order: tag_order)

      out = described_class.render(
        described_class.sort(entries, tag_order: %w[param option return])
      )

      expect(out).to eq([
                          "# @param [Hash] opts the options to create a message with.\n",
                          "# @option opts [String] :subject The subject\n",
                          "# @option opts [String] :from ('nobody') From address\n",
                          "# @param [String] name the name\n",
                          "# @return [Object]\n"
                        ])
    end

    it 'supports name-first @param syntax' do
      entries = described_class.parse([
                                        "# @return [Object]\n",
                                        "# @param foo [Object] Param documentation.\n"
                                      ], tag_order: tag_order)

      out = described_class.render(
        described_class.sort(entries, tag_order: %w[param return])
      )

      expect(out).to eq([
                          "# @param foo [Object] Param documentation.\n",
                          "# @return [Object]\n"
                        ])
    end
  end

  describe '.merge' do
    it 'preserves existing tag text exactly while sorting in generated missing tags' do
      out = described_class.merge(
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

      expect(out).to eq([
                          "# Existing docs\n",
                          "# @param [Object] foo blah-blah\n",
                          "# @raise [ArgumentError]\n",
                          "# @return [Object]\n"
                        ])
    end
  end
end
