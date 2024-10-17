const fs = require('fs');
const path = require('path');
const os = require('os');
const core = require('@actions/core');

function createConfigFile(apiHost, apiProxy, apiSslVerify, apiUserAgent) {
  if (apiHost) {
    apiHost = `https://${apiHost}`;
  }
  try {
    const configContent = `# Default configuration
[default]
# The API host to connect to (default: api.cloudsmith.io).
api_host=${apiHost || ''}

# The API proxy to connect through (default: None).
api_proxy=${apiProxy || ''}

# Whether to verify SSL connection to the API (default: True)
api_ssl_verify=${apiSslVerify || 'true'}

# The user agent to use for requests (default: calculated).
api_user_agent=${apiUserAgent || ''}
`;

    const configPath = getConfigPath();
    const configDir = path.dirname(configPath);

    // Create directory if it doesn't exist
    if (!fs.existsSync(configDir)) {
      fs.mkdirSync(configDir, { recursive: true });
    }

    // Write config file
    fs.writeFileSync(configPath, configContent, 'utf8');
    core.info(`Config file created at: ${configPath}`);
  } catch (error) {
    core.warning(`Failed to create config file: ${error.message}`);
  }
}

function getConfigPath() {
  const homeDir = os.homedir();
  
  if (process.platform === 'win32') {
    const localAppData = process.env.LOCALAPPDATA || path.join(homeDir, 'AppData', 'Local');
    const roamingAppData = process.env.APPDATA || path.join(homeDir, 'AppData', 'Roaming');
    
    // Check if Local path exists, otherwise use Roaming
    const baseDir = fs.existsSync(localAppData) ? localAppData : roamingAppData;
    return path.join(baseDir, 'cloudsmith', 'config.ini');
  } else {
    return path.join(homeDir, '.cloudsmith', 'config.ini');
  }
}

module.exports = { createConfigFile };
