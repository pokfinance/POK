const pok = artifacts.require("POKPool");

module.exports = function (deployer) {
  deployer.deploy(pok);
};
