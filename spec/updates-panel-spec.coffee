UpdatesPanel = require '../lib/updates-panel'
PackageManager = require '../lib/package-manager'
SettingsView = require '../lib/settings-view'

describe 'UpdatesPanel', ->
  panel = null
  settingsView = null
  packageManager = null
  [resolveOutdated, rejectOutdated] = []

  beforeEach ->
    settingsView = new SettingsView
    packageManager = new PackageManager
    # This spy is only needed for the Check for Updates specs,
    # but we have to instantiate it here because we need to pass the spy to the UpdatesPanel
    spyOn(packageManager, 'getOutdated').andReturn(new Promise((resolve, reject) -> [resolveOutdated, rejectOutdated] = [resolve, reject]))
    panel = new UpdatesPanel(settingsView, packageManager)
    jasmine.attachToDOM(panel.element)

  it "shows updates when updates are available", ->
    pack =
      name: 'test-package'
      description: 'some description'
      latestVersion: '99.0.0'
      version: '1.0.0'

    # skip packman stubbing
    panel.beforeShow(updates: [pack])
    expect(panel.refs.updatesContainer.children.length).toBe(1)

  it "shows a message when updates are not available", ->
    panel.beforeShow(updates: [])
    expect(panel.refs.updatesContainer.children.length).toBe(0)
    expect(panel.refs.noUpdatesMessage.style.display).not.toBe('none')

  describe "version pinned packages message", ->
    it 'shows a message when there are pinned version packages', ->
      spyOn(packageManager, 'getVersionPinnedPackages').andReturn(['foo', 'bar', 'baz'])
      panel.beforeShow(updates: [])
      expect(panel.refs.versionPinnedPackagesMessage.style.display).not.toBe('none')

    it 'does not show a message when there are no version pinned packages', ->
      spyOn(packageManager, 'getVersionPinnedPackages').andReturn([])
      panel.beforeShow(updates: [])
      expect(panel.refs.versionPinnedPackagesMessage.style.display).toBe('none')

  describe "the Update All button", ->
    packA =
      name: 'test-package-a'
      description: 'some description'
      latestVersion: '99.0.0'
      version: '1.0.0'
    packB =
      name: 'test-package-b'
      description: 'some description'
      latestVersion: '99.0.0'
      version: '1.0.0'
    packC =
      name: 'test-package-c'
      description: 'some description'
      latestVersion: '99.0.0'
      version: '1.0.0'

    [cardA, cardB, cardC] = []
    [resolveA, resolveB, resolveC, rejectA, rejectB, rejectC] = []

    beforeEach ->
      # skip packman stubbing
      panel.beforeShow(updates: [packA, packB, packC])

      [cardA, cardB, cardC] = panel.packageCards

      spyOn(cardA, 'update').andReturn(new Promise((resolve, reject) -> [resolveA, rejectA] = [resolve, reject]))
      spyOn(cardB, 'update').andReturn(new Promise((resolve, reject) -> [resolveB, rejectB] = [resolve, reject]))
      spyOn(cardC, 'update').andReturn(new Promise((resolve, reject) -> [resolveC, rejectC] = [resolve, reject]))

      atom.config.set("settings-view.packageUpdateConcurrency", -1)

    it 'attempts to update all packages and prompts to restart if at least one package updates successfully', ->
      expect(atom.notifications.getNotifications().length).toBe 0
      expect(panel.refs.updateAllButton).toBeVisible()

      panel.updateAll()

      resolveA()
      rejectB('Error updating package')

      waits 0
      runs ->
        expect(atom.notifications.getNotifications().length).toBe 0

        resolveC()

      waitsFor ->
        atom.notifications.getNotifications().length is 1

      runs ->
        spyOn(atom, 'restartApplication')
        atom.notifications.getNotifications()[0].options.buttons[0].onDidClick()
        expect(atom.restartApplication).toHaveBeenCalled()

    it 'works with queue enabled', ->
      expect(panel.refs.updateAllButton).not.toBeDisabled()
      atom.config.set("settings-view.packageUpdateConcurrency", 2)

      panel.updateAll()

      resolveA()
      resolveB()
      resolveC()

      waitsFor ->
        panel.refs.updateAllButton.style.display is 'none'

    it 'becomes hidden if all updates succeed', ->
      expect(panel.refs.updateAllButton).not.toBeDisabled()

      panel.updateAll()

      expect(panel.refs.updateAllButton).toBeDisabled()

      resolveA()
      resolveB()
      resolveC()

      waitsFor ->
        panel.refs.updateAllButton.style.display is 'none'

    it 'remains enabled and visible if not all updates succeed', ->
      expect(panel.refs.updateAllButton).not.toBeDisabled()

      panel.updateAll()

      expect(panel.refs.updateAllButton).toBeDisabled()

      resolveA()
      rejectB('Error updating package')
      resolveC()

      waitsFor ->
        panel.refs.updateAllButton.disabled is false

      runs ->
        expect(panel.refs.updateAllButton).toBeVisible()

    it 'does not attempt to update packages that are already updating', ->
      cardA.update()
      packageManager.emitPackageEvent 'updating', packA
      panel.updateAll()

      expect(cardA.update.calls.length).toBe 1

  describe 'the Check for Updates button', ->
    pack =
      name: 'test-package'
      description: 'some description'
      latestVersion: '99.0.0'
      version: '1.0.0'

    beforeEach ->
      # skip packman stubbing - without this, getOutdated() is called another time
      # this is not an issue in actual usage as getOutdated() isn't blocked on a spy
      panel.beforeShow(updates: [pack])

    it 'disables itself when clicked until the list of outdated packages is returned', ->
      # Updates panel checks for updates on initialization so resolve the promise
      resolveOutdated()

      waits 0
      runs ->
        expect(panel.refs.checkButton.disabled).toBe false

        panel.checkForUpdates()
        expect(panel.refs.checkButton.disabled).toBe true

        resolveOutdated()

      waits 0
      runs ->
        expect(panel.refs.checkButton.disabled).toBe false

    it 'clears the outdated cache when checking for updates', ->
      # This spec just tests that we're passing the clearCache bool through, not the actual implementation
      # For that, look at the PackageManager specs
      resolveOutdated()
      waits 0
      runs ->
        panel.refs.checkButton.click()
        expect(packageManager.getOutdated).toHaveBeenCalledWith true

    it 'is disabled when packages are updating', ->
      # Updates panel checks for updates on initialization so resolve the promise
      resolveOutdated()

      waits 0
      runs ->
        expect(panel.refs.checkButton.disabled).toBe false

        packageManager.emitPackageEvent 'updating', {name: 'packA'}
        expect(panel.refs.checkButton.disabled).toBe true

        packageManager.emitPackageEvent 'updating', {name: 'packB'}
        expect(panel.refs.checkButton.disabled).toBe true

        packageManager.emitPackageEvent 'updated', {name: 'packB'}
        expect(panel.refs.checkButton.disabled).toBe true

        packageManager.emitPackageEvent 'update-failed', {name: 'packA'}
        expect(panel.refs.checkButton.disabled).toBe false
