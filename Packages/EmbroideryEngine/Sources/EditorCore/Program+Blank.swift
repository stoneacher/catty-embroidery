import ProgramModel

public extension Program {
    /// The program the editor starts from when nothing has been picked (US-405).
    static var blank: Program {
        Program()
    }
}
