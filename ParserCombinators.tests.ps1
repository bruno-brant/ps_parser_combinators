using module "./ParserCombinators.psm1"

Describe "ParserCombinators" {
	It "should throw an error when a script block isn't provided" {
		{ [Parser]::new() } | Should Throw
	}

	It "should return the result of the parser when Parse is called" {
		$parser = [Parser]::new({
				param([Input]$inputString)
		
				$value = $inputString.Text.Substring(0, 2)
				$remainder = $inputString.Advance(2)

				return [Result]::Success($value, $remainder)
			})
	
		$inputString = [Input]::new("test")

		$actual = $parser.Parse($inputString)

		$actual | Should Not Be $null
		$actual.IsSuccess | Should Be $true
		$actual.RemainingInput.RemainingText() | Should Be "st"
		$actual.Value | Should Be "te"
	}
}

Describe "Combinators" {
	Context "Then" {
		It "should chain two parsers together" {
			$parserA = [Parser]::Char('a')
			$parserB = [Parser]::Char('b')
			$combinedParser = $parserA.Then({ $parserB }.GetNewClosure())

			$inputString = [Input]::new("abc")

			$actual = $combinedParser.Parse($inputString)

			$actual | Should Not Be $null
			$actual.IsSuccess | Should Be $true
			$actual.RemainingInput.RemainingText() | Should Be "c"
			$actual.Value | Should Be 'b'
		}
	}

	Context "Not" {
		It "should invert a successful result to a failure" {
			$parser = [Parser]::Char('t').Not()

			$inputString = [Input]::new("test")

			$actual = $parser.Parse($inputString)

			$actual | Should Not Be $null
			$actual.IsSuccess | Should Be $false
			$actual.RemainingInput.RemainingText() | Should Be "test"
			$actual.Value | Should Be $null
		}
	}

	Context "Many" {
		It "should match zero or more occurrences of the parser" {
			$parser = [Parser]::Char('a').Many()

			$inputString = [Input]::new("aaabc")

			$actual = $parser.Parse($inputString)

			$actual | Should Not Be $null
			$actual.IsSuccess | Should Be $true
			$actual.RemainingInput.RemainingText() | Should Be "bc"
			$actual.Value | Should Be @('a', 'a', 'a')
		}
	}

	Context "Or" {
		It "should return the first parser if it passes" {
			$parserA = [Parser]::Char('a')
			$parserB = [Parser]::Char('b')
			$combinedParser = $parserA.Or($parserB)

			$inputString = [Input]::new("abc")

			$actual = $combinedParser.Parse($inputString)

			$actual | Should Not Be $null
			$actual.IsSuccess | Should Be $true
			$actual.RemainingInput.RemainingText() | Should Be "bc"
			$actual.Value | Should Be 'a'
		}
		
		It "should try the second parser if the first fails" {
			$parserA = [Parser]::Char('a')
			$parserB = [Parser]::Char('b')
			$combinedParser = $parserA.Or($parserB)

			$inputString = [Input]::new("bcd")

			$actual = $combinedParser.Parse($inputString)

			$actual | Should Not Be $null
			$actual.IsSuccess | Should Be $true
			$actual.RemainingInput.RemainingText() | Should Be "cd"
			$actual.Value | Should Be 'b'
		}

		It "should fail if both parsers fail" {
			$parserA = [Parser]::Char('a')
			$parserB = [Parser]::Char('b')
			$combinedParser = $parserA.Or($parserB)

			$inputString = [Input]::new("cde")

			$actual = $combinedParser.Parse($inputString)

			$actual | Should Not Be $null
			$actual.IsSuccess | Should Be $false
			$actual.RemainingInput.RemainingText() | Should Be "cde"
			$actual.Value | Should Be $null
		}
	}

	Context "Token" {
		It "should ignore leading and trailing whitespace" {
			$parser = [Parser]::Char('a').Token()

			$inputString = [Input]::new("   a   bc")

			$actual = $parser.Parse($inputString)

			$actual | Should Not Be $null
			$actual.IsSuccess | Should Be $true
			$actual.RemainingInput.RemainingText() | Should Be "bc"
			$actual.Value | Should Be 'a'
		}

		It "should fail if the main parser fails" {
			$parser = [Parser]::Char('a').Token()
			$inputString = [Input]::new("   b   bc")

			$actual = $parser.Parse($inputString)

			$actual | Should Not Be $null
			$actual.IsSuccess | Should Be $false
			$actual.RemainingInput.RemainingText() | Should Be "   b   bc"
			$actual.Value | Should Be $null
		}
	}
}

Describe "Char parser" {
	Context "Predicate" {
		It "should match a character based on a predicate" {
			$parser = [Parser]::Char({ param([char]$c) return $c -match '[a-z]' })
			$inputString = [Input]::new("abc")

			$actual = $parser.Parse($inputString)

			$actual | Should Not Be $null
			$actual.IsSuccess | Should Be $true
			$actual.RemainingInput.RemainingText() | Should Be "bc"
			$actual.Value | Should Be 'a'
		}

		It "should fail if the character doesn't satisfy the predicate" {
			$parser = [Parser]::Char({ param([char]$c) return $c -match '[a-z]' })
			$inputString = [Input]::new("1bc")

			$actual = $parser.Parse($inputString)

			$actual | Should Not Be $null
			$actual.IsSuccess | Should Be $false
			$actual.RemainingInput.RemainingText() | Should Be "1bc"
			$actual.Value | Should Be $null
		}
	}

	Context "Single char" {
		It "should match a single character" {
			$parser = [Parser]::Char('a')
			$inputString = [Input]::new("abc")

			$actual = $parser.Parse($inputString)

			$actual | Should Not Be $null
			$actual.IsSuccess | Should Be $true
			$actual.RemainingInput.RemainingText() | Should Be "bc"
			$actual.Value | Should Be 'a'
		}

		It "should fail if the character doesn't match" {
			$parser = [Parser]::Char('a')
			$inputString = [Input]::new("xbc")

			$actual = $parser.Parse($inputString)

			$actual | Should Not Be $null
			$actual.IsSuccess | Should Be $false
			$actual.RemainingInput.RemainingText() | Should Be "xbc"
			$actual.Value | Should Be $null
		}
	}
	
}

Describe "CharIn parser" {
	It "should match a character in the set" {
		$parser = [Parser]::CharIn(@('a', 'b', 'c'))
		$inputString = [Input]::new("abc")

		$actual = $parser.Parse($inputString)

		$actual | Should Not Be $null
		$actual.IsSuccess | Should Be $true
		$actual.RemainingInput.RemainingText() | Should Be "bc"
		$actual.Value | Should Be 'a'
	}

	It "should fail if the character is not in the set" {
		$parser = [Parser]::CharIn(@('a', 'b', 'c'))
		$inputString = [Input]::new("xbc")

		$actual = $parser.Parse($inputString)

		$actual | Should Not Be $null
		$actual.IsSuccess | Should Be $false
		$actual.RemainingInput.RemainingText() | Should Be "xbc"
		$actual.Value | Should Be $null
	}
}

Describe "CharExcept parser" {
	It "should match a character not in the set" {
		$parser = [Parser]::CharExcept(@('a', 'b', 'c'))
		$inputString = [Input]::new("xabc")

		$actual = $parser.Parse($inputString)

		$actual | Should Not Be $null
		$actual.IsSuccess | Should Be $true
		$actual.RemainingInput.RemainingText() | Should Be "abc"
		$actual.Value | Should Be 'x'
	}

	It "should fail if the character is in the set" {
		$parser = [Parser]::CharExcept(@('a', 'b', 'c'))
		$inputString = [Input]::new("abc")

		$actual = $parser.Parse($inputString)

		$actual | Should Not Be $null
		$actual.IsSuccess | Should Be $false
		$actual.RemainingInput.RemainingText() | Should Be "abc"
		$actual.Value | Should Be $null
	}
}

Describe "Digit Parser" {
	It "should match a digit character" {
		$parser = [Parser]::Digit()
		$inputString = [Input]::new("1abc")

		$actual = $parser.Parse($inputString)

		$actual | Should Not Be $null
		$actual.IsSuccess | Should Be $true
		$actual.RemainingInput.RemainingText() | Should Be "abc"
		$actual.Value | Should Be '1'
	}

	It "should fail if the character is not a digit" {
		$parser = [Parser]::Digit()
		$inputString = [Input]::new("xabc")

		$actual = $parser.Parse($inputString)

		$actual | Should Not Be $null
		$actual.IsSuccess | Should Be $false
		$actual.RemainingInput.RemainingText() | Should Be "xabc"
		$actual.Value | Should Be $null
	}
}

Describe "Letter Parser" {
	It "should match a letter character" {
		$parser = [Parser]::Letter()
		$inputString = [Input]::new("a123")

		$actual = $parser.Parse($inputString)

		$actual | Should Not Be $null
		$actual.IsSuccess | Should Be $true
		$actual.RemainingInput.RemainingText() | Should Be "123"
		$actual.Value | Should Be 'a'
	}

	It "should fail if the character is not a letter" {
		$parser = [Parser]::Letter()
		$inputString = [Input]::new("1abc")

		$actual = $parser.Parse($inputString)

		$actual | Should Not Be $null
		$actual.IsSuccess | Should Be $false
		$actual.RemainingInput.RemainingText() | Should Be "1abc"
		$actual.Value | Should Be $null
	}
}

Describe "String Parser" {
	It "should match a specific string" {
		$parser = [Parser]::String("hello")
		$inputString = [Input]::new("hello world")

		$actual = $parser.Parse($inputString)

		$actual | Should Not Be $null
		$actual.IsSuccess | Should Be $true
		$actual.RemainingInput.RemainingText() | Should Be " world"
		$actual.Value | Should Be "hello"
	}

	It "should fail if the string doesn't match" {
		$parser = [Parser]::String("hello")
		$inputString = [Input]::new("hi world")

		$actual = $parser.Parse($inputString)

		$actual | Should Not Be $null
		$actual.IsSuccess | Should Be $false
		$actual.RemainingInput.RemainingText() | Should Be "hi world"
		$actual.Value | Should Be $null
	}
}
