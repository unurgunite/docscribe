# frozen_string_literal: true

require 'docscribe/inline_rewriter'

Ins = Struct.new(:names)

RSpec.describe Docscribe::InlineRewriter do
  describe '#existing_attr_names' do
    it 'returns empty hash for empty lines' do
      expect(described_class.send(:existing_attr_names, [])).to be_empty
    end

    it 'detects attribute names from @!attribute lines' do
      lines = ['# @!attribute [r] name', '# @!attribute [w] age']
      result = described_class.send(:existing_attr_names, lines)
      expect(result).to eq('name' => true, 'age' => true)
    end

    it 'skips non-attribute lines' do
      lines = ['# @return [String]', '# plain comment', '# @!attribute name']
      result = described_class.send(:existing_attr_names, lines)
      expect(result).to eq('name' => true)
    end
  end

  describe '#missing_attr_names' do
    let(:ins) { Ins.new(%i[name age email]) }

    it 'returns nil for all names present in existing lines' do
      lines = ['# @!attribute [r] name', '# @!attribute [r] age', '# @!attribute [r] email']
      result = described_class.send(:missing_attr_names, ins, lines)
      expect(result).to be_empty
    end

    it 'returns missing name not in existing lines' do
      lines = ['# @!attribute [r] name']
      result = described_class.send(:missing_attr_names, ins, lines)
      expect(result).to eq(%i[age email])
    end
  end

  describe '#existing_attr_line_index' do
    it 'returns index of line with matching attribute name' do
      lines = ['# some doc', '# @!attribute [r] name', '#   @return [String]']
      result = described_class.send(:existing_attr_line_index, lines, 'name')
      expect(result).to eq(1)
    end

    it 'returns nil when name not found' do
      lines = ['# @!attribute [r] name']
      result = described_class.send(:existing_attr_line_index, lines, 'age')
      expect(result).to be_nil
    end
  end

  describe '#existing_lines_contain_tag?' do
    let(:lines) do
      [
        '# @!attribute [r] name',
        '#   @return [String]',
        '# @!attribute [r] age',
        '#   @return [Integer]'
      ]
    end

    it 'finds tag after attribute line' do
      result = described_class.send(:existing_lines_contain_tag?, lines, 0, 'return')
      expect(result).to be(true)
    end

    it 'stops at next top-level directive' do
      result = described_class.send(:existing_lines_contain_tag?, lines, 0, 'param')
      expect(result).to be(false)
    end

    it 'returns false when no tag present' do
      single = ['# @!attribute [r] name']
      result = described_class.send(:existing_lines_contain_tag?, single, 0, 'return')
      expect(result).to be(false)
    end
  end

  describe '#attr_return_missing?' do
    let(:lines) { ['# @!attribute [r] name', '#   @return [String]'] }

    it 'returns false when return tag exists and access is r' do
      result = described_class.send(:attr_return_missing?, :r, lines, 0)
      expect(result).to be(false)
    end

    it 'returns true when return tag exists but access is w' do
      result = described_class.send(:attr_return_missing?, :w, lines, 0)
      expect(result).to be(false)
    end

    it 'returns true when return tag missing and access is r' do
      lines = ['# @!attribute [r] name']
      result = described_class.send(:attr_return_missing?, :r, lines, 0)
      expect(result).to be(true)
    end
  end

  describe '#attr_param_missing?' do
    let(:lines) { ['# @!attribute [w] name', '#   @param value [String]'] }

    it 'returns false when param tag exists and access is w' do
      result = described_class.send(:attr_param_missing?, :w, lines, 0)
      expect(result).to be(false)
    end

    it 'returns false when param tag exists and access is r' do
      result = described_class.send(:attr_param_missing?, :r, lines, 0)
      expect(result).to be(false)
    end

    it 'returns true when param tag missing and access is w' do
      lines = ['# @!attribute [w] name']
      result = described_class.send(:attr_param_missing?, :w, lines, 0)
      expect(result).to be(true)
    end
  end

  describe '#format_attribute_param_tag' do
    it 'formats name_type style' do
      result = described_class.send(:format_attribute_param_tag, '  ', 'value', 'String', style: 'name_type')
      expect(result).to eq('  #   @param value [String]')
    end

    it 'formats type_name style' do
      result = described_class.send(:format_attribute_param_tag, '  ', 'value', 'String', style: 'type_name')
      expect(result).to eq('  #   @param [String] value')
    end
  end

  describe '#extract_separators' do
    let(:sep_re) { /^\s*#\s*\r?\n$/ }

    it 'extracts leading separator lines' do
      lines = ["#\n", 'some text']
      result = described_class.send(:extract_separators, lines, sep_re)
      expect(result).to eq(["#\n"])
    end

    it 'does not extract text lines' do
      lines = ['text']
      result = described_class.send(:extract_separators, lines, sep_re)
      expect(result).to be_empty
    end

    it 'removes separator lines from original array' do
      lines = ["#\n", "  #\n", 'text']
      described_class.send(:extract_separators, lines, sep_re)
      expect(lines).to eq(['text'])
    end
  end

  describe '#merge_chunk_into_out' do
    let(:sep_re) { /^\s*#\s*\r?\n$/ }

    it 'appends chunk lines to out' do
      out = []
      described_class.send(:merge_chunk_into_out, "line1\nline2", out, sep_re)
      expect(out).to eq(%W[line1\n line2])
    end
  end

  describe '#merge_text_for_pos' do
    it 'returns nil for empty chunks' do
      result = described_class.send(:merge_text_for_pos, [])
      expect(result).to be_nil
    end

    it 'merges chunks sorted by sort key' do
      chunks = [[2, "b\n"], [1, "a\n"]]
      result = described_class.send(:merge_text_for_pos, chunks)
      expect(result).to eq("a\nb\n")
    end

    it 'skips nil chunks' do
      chunks = [[1, nil], [2, 'text']]
      result = described_class.send(:merge_text_for_pos, chunks)
      expect(result).to eq('text')
    end

    it 'includes chunk1 text in merged output' do
      chunks = [[1, "#\nchunk1"], [2, "#\nchunk2"]]
      expect(described_class.send(:merge_text_for_pos, chunks)).to include('chunk1')
    end

    it 'includes chunk2 text in merged output' do
      chunks = [[1, "#\nchunk1"], [2, "#\nchunk2"]]
      expect(described_class.send(:merge_text_for_pos, chunks)).to include('chunk2')
    end
  end
end
