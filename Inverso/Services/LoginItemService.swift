import ServiceManagement

/// The part of SMAppService we use. Lets tests substitute a fake.
@MainActor
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}
