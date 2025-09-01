<# Represents the text input for the parser #>
class Input {
	hidden [string]$Text
	hidden [int]$Position

	Input([string]$text) {
		$this.Text = $text
		$this.Position = 0
	}

	Input([string]$text, [int]$position) {
		$this.Text = $text
		$this.Position = $position
	}

	[bool]AtEnd() {
		return $this.Position -ge $this.Text.Length
	}

	[char]CurrentChar() {
		if ($this.AtEnd()) {
			throw "End of input reached"
		}
		return $this.Text[$this.Position]
	}

	[Input] Advance([int]$steps = 1) {
		return [Input]::new($this.Text, $this.Position + $steps)
	}

	[string]RemainingText() {
		if ($this.AtEnd()) {
			return ""
		}
		return $this.Text.Substring($this.Position)
	}
}

<# Represents the result of a parser operation #>
class Result {
	[object]$Value
	[Input]$RemainingInput
	[bool]$IsSuccess

	Result([object]$value, [Input]$remainingInput, [bool]$isSuccess) {
		$this.Value = $value
		$this.RemainingInput = $remainingInput
		$this.IsSuccess = $isSuccess
	}

	<# Builds a successful result #>
	static [Result] Success($value, [Input]$remainingInput) {
		return [Result]::new($value, $remainingInput, $true)
	}

	<# Builds a failure result #>
	static [Result] Failure([Input]$remainingInput) {
		return [Result]::new($null, $remainingInput, $false)
	}

	<# If the result is successful, invoke the success handler #>
	[Result] IfSuccess([scriptblock]$onSuccess) {
		if ($this.IsSuccess) {
			return & $onSuccess $this
		} 
		
		return $this
	}

	<# If the result is a failure, invoke the failure handler #>
	[Result] IfFailure([scriptblock]$onFailure) {
		if (-not $this.IsSuccess) {
			return & $onFailure $this
		} 
		
		return $this
	}
}

class Parser {
	hidden [scriptblock]$parseFunction

	Parser([scriptblock]$parseFunction) {
		if (-not $parseFunction) {
			throw "Argument is not a script block"
		}
		
		$this.parseFunction = $parseFunction
	}

	<# Calls the parser's script block with the input string #>
	[Result] Parse([Input]$inputString) {
		[Result] $result = & $this.parseFunction $inputString
		
		# Don't consume input on failure
		if (-not $result.IsSuccess) {
			$result = [Result]::Failure($inputString)
		}
		
		return $result
	}

	<# 
	.SYNOPSIS
		Chains two parsers together 
	.PARAMETER nextBlock
		A script block that takes the result of the first parser and returns a new parser
	#>
	[Parser] Then([scriptblock]$nextBlock) {
		$thisObject = $this
		
		return [Parser]::new({
				param([Input]$inputString)
				$result = $thisObject.Parse($inputString)
			
				return $result.IfSuccess({
						param([Result]$firstResult)
						$secondParser = (& $nextBlock $firstResult)
						return $secondParser.Parse($firstResult.RemainingInput)
					})
			}.GetNewClosure())
	}

	[Parser] Then([Parser]$nextParser) {
		return $this.Then({ 
			param([Result]$r) 
			if ($r.IsSuccess) { 
				return $nextParser 
			} else {
				return [Parser]::new({
					param([Input]$inputString)
					return [Result]::Failure($inputString)
				})
			} 
		}.GetNewClosure())
	}

	<# Inverts the result of the parser #>
	[Parser] Not() {
		$object = $this
		return [Parser]::new({
				param([Input]$inputString)

				$result = $object.Parse($inputString)
				if ($result.IsSuccess) {
					return [Result]::Failure($inputString)
				}
				else {
					return [Result]::Success($null, $inputString)
				}
			}.GetNewClosure())
	}

	<# Matches zero or more occurrences of the parser #>
	[Parser] Many() {
		$thisObject = $this
		return [Parser]::new({
				param([Input]$inputString)
		
				$remainder = $inputString
				$values = @()
				$result = $thisObject.Parse($remainder)

				while ($result.IsSuccess) {
					if ($remainder.RemainingText() -eq $result.RemainingInput.RemainingText()) {
						break
					}

					$values += $result.Value
					$remainder = $result.RemainingInput
					$result = $thisObject.Parse($remainder)
				}

				return [Result]::Success($values, $remainder)
			}.GetNewClosure())
	}

	[Parser] Or([Parser]$otherParser) {
		$thisObject = $this
		return [Parser]::new({
				param([Input]$inputString)

				$result = $thisObject.Parse($inputString)
				if ($result.IsSuccess) {
					return $result
				}

				return $otherParser.Parse($inputString)
			}.GetNewClosure())
	}

	[Parser] Token() {
		$thisObject = $this

		return [Parser]::Whitespace().Many().Then($thisObject).Then({
				param([Result]$thisResult)
				
				if (-not $thisResult.IsSuccess) {
					return [Parser]::new({
							param([Input]$inputString)
							return [Result]::Failure($inputString)
						}.GetNewClosure())
				}

				return [Parser]::Whitespace().Many().Then({
						param([Result]$trailingWhitespace)
						return [Parser]::ConstantParser($thisResult.Value)
					}.GetNewClosure())
			}.GetNewClosure())
	}

	<# Returns a parser that always succeeds with the given value #>
	static [Parser] ConstantParser([object]$value) {
		return [Parser]::new({
				param([Input]$inputString)
				return [Result]::Success($value, $inputString)
			}.GetNewClosure())
	}

	<# Matches a character based on a predicate function #>
	static [Parser] Char([System.Predicate[char]]$predicate) {
		if (-not $predicate) {
			throw "Argument is not a valid predicate"
		}

		$prd = $predicate
		return [Parser]::new({
				param([Input]$inputString)
			
				if ($inputString.AtEnd()) {
					return [Result]::Failure($inputString)
				}

				$currentChar = $inputString.CurrentChar()
				if ($prd.Invoke($currentChar)) {
					return [Result]::Success($currentChar, $inputString.Advance(1))
				}

				return [Result]::Failure($inputString)
			}.GetNewClosure())
	}

	<# Matches a specific character #>
	static [Parser] Char([char]$charToMatch) {
		return [Parser]::Char({ param([char]$c) $c -eq $charToMatch }.GetNewClosure())
	}

	<# Matches any character in the provided set #>
	static [Parser] CharIn([char[]]$chars) {
		return [Parser]::Char({ param([char]$c) $chars -contains $c }.GetNewClosure())
	}

	<# Matches any character not in the provided set #>
	static [Parser] CharExcept([char[]]$chars) {
		return [Parser]::Char({ param([char]$c) -not ($chars -contains $c) }.GetNewClosure())
	}

	<# Matches any single character #>
	static [Parser] AnyChar() {
		return [Parser]::Char({ param([char]$c) $true }.GetNewClosure())
	}

	<# Matches a whitespace character #>
	static [Parser] Whitespace() {
		return [Parser]::Char({ param([char]$c) $c -match '\s' }.GetNewClosure())
	}

	<# Matches a digit character #>
	static [Parser] Digit() {
		return [Parser]::Char({ param([char]$c) $c -match '\d' }.GetNewClosure())
	}

	<# Matches a letter character #>
	static [Parser] Letter() {
		return [Parser]::Char({ param([char]$c) $c -match '[a-zA-Z]' }.GetNewClosure())
	}

	<# Matches a specific string #>
	static [Parser] String([string]$stringToMatch) {
		return [Parser]::new({
				param([Input]$inputString)
			
				$currentInput = $inputString
				foreach ($char in $stringToMatch.ToCharArray()) {
					if ($currentInput.AtEnd() -or $currentInput.CurrentChar() -ne $char) {
						return [Result]::Failure($inputString)
					}
					$currentInput = $currentInput.Advance(1)
				}

				return [Result]::Success($stringToMatch, $currentInput)
			}.GetNewClosure())
	}
}
