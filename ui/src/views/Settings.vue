<!--
  Copyright (C) 2026 Nethesis S.r.l.
  SPDX-License-Identifier: GPL-3.0-or-later
-->
<template>
  <cv-grid fullWidth>
    <cv-row>
      <cv-column class="page-title">
        <h2>{{ $t("settings.title") }}</h2>
      </cv-column>
    </cv-row>
    <cv-row v-if="error.getConfiguration">
      <cv-column>
        <NsInlineNotification
          kind="error"
          :title="$t('action.get-configuration')"
          :description="error.getConfiguration"
          :showCloseButton="false"
        />
      </cv-column>
    </cv-row>
    <cv-row v-if="isRouteMissing">
      <cv-column>
        <NsInlineNotification
          kind="warning"
          :title="$t('settings.no_route_title')"
          :description="$t('settings.no_route_description')"
          :showCloseButton="false"
        />
      </cv-column>
    </cv-row>
    <cv-row>
      <cv-column>
        <cv-tile light>
          <cv-form @submit.prevent="configureModule">
            <h4 class="mg-bottom-md">{{ $t("settings.web_access") }}</h4>
            <NsInlineNotification
              kind="info"
              :title="$t('settings.public_service_title')"
              :description="$t('settings.public_service_description')"
              :showCloseButton="false"
            />
            <NsToggle
              value="privateCreators"
              :label="$t('settings.private_creators')"
              v-model="isPrivateCreators"
              :disabled="stillLoading"
              class="mg-bottom"
            >
              <template #tooltip>
                {{ $t("settings.private_creators_tooltip") }}
              </template>
              <template slot="text-left">{{
                $t("settings.disabled")
              }}</template>
              <template slot="text-right">{{
                $t("settings.enabled")
              }}</template>
            </NsToggle>
            <NsTextInput
              :label="$t('settings.privatebin_fqdn')"
              placeholder="privatebin.example.org"
              v-model.trim="host"
              class="mg-bottom maxwidth"
              :invalid-message="$t(error.host)"
              :disabled="stillLoading"
              ref="host"
            />
            <NsToggle
              value="letsEncrypt"
              :label="core.$t('apps_lets_encrypt.request_https_certificate')"
              v-model="isLetsEncryptEnabled"
              :disabled="stillLoading"
              class="mg-bottom"
            >
              <template #tooltip>
                <div class="mg-bottom-sm">
                  {{ core.$t("apps_lets_encrypt.lets_encrypt_tips") }}
                </div>
                <div class="mg-bottom-sm">
                  <cv-link @click="goToCertificates">
                    {{ core.$t("apps_lets_encrypt.go_to_tls_certificates") }}
                  </cv-link>
                </div>
              </template>
              <template slot="text-left">{{
                $t("settings.disabled")
              }}</template>
              <template slot="text-right">{{
                $t("settings.enabled")
              }}</template>
            </NsToggle>
            <NsInlineNotification
              v-if="isLetsEncryptCurrentlyEnabled && !isLetsEncryptEnabled"
              kind="warning"
              :title="
                core.$t('apps_lets_encrypt.lets_encrypt_disabled_warning')
              "
              :description="
                core.$t(
                  'apps_lets_encrypt.lets_encrypt_disabled_warning_description',
                  {
                    node: status.node_ui_name
                      ? status.node_ui_name
                      : status.node,
                  }
                )
              "
              :showCloseButton="false"
            />

            <cv-accordion ref="accordion" class="maxwidth mg-bottom mg-top">
              <cv-accordion-item :open="toggleAccordion[0]">
                <template slot="title">{{ $t("settings.advanced") }}</template>
                <template slot="content">
                  <h4 class="mg-bottom-md">{{ $t("settings.branding") }}</h4>
                  <NsTextInput
                    :label="$t('settings.name')"
                    placeholder="PrivateBin"
                    v-model.trim="name"
                    :helper-text="$t('settings.name_helper')"
                    :invalid-message="$t(error.name)"
                    :disabled="stillLoading"
                    class="mg-bottom maxwidth"
                    ref="name"
                  />
                  <cv-text-area
                    :label="$t('settings.notice')"
                    v-model.trim="notice"
                    :helper-text="$t('settings.notice_helper')"
                    :invalid-message="$t(error.notice)"
                    :disabled="stillLoading"
                    class="mg-bottom maxwidth"
                    ref="notice"
                  />
                  <cv-text-area
                    :label="$t('settings.info')"
                    v-model.trim="info"
                    :helper-text="$t('settings.info_helper')"
                    :invalid-message="$t(error.info)"
                    :disabled="stillLoading"
                    class="mg-bottom maxwidth"
                    ref="info"
                  />
                  <div class="mg-bottom maxwidth">
                    <div class="bx--label">{{ $t("settings.logo") }}</div>
                    <div class="logo-row mg-bottom-sm">
                      <img
                        v-if="logoPreview"
                        :src="logoPreview"
                        class="logo-preview"
                        alt=""
                      />
                      <span v-else class="logo-status">{{
                        isLogoSet && !isLogoReset
                          ? $t("settings.logo_custom")
                          : $t("settings.logo_original")
                      }}</span>
                      <NsButton
                        v-if="(isLogoSet && !isLogoReset) || logoData"
                        kind="tertiary"
                        size="small"
                        :icon="Reset20"
                        :disabled="stillLoading"
                        @click="resetLogo"
                        >{{ $t("settings.logo_reset") }}</NsButton
                      >
                    </div>
                    <cv-file-uploader
                      :key="logoUploaderKey"
                      kind="button"
                      :buttonLabel="$t('settings.logo_choose')"
                      :helperText="$t('settings.logo_helper')"
                      accept=".png,.jpg,.jpeg,image/png,image/jpeg"
                      :multiple="false"
                      :removable="false"
                      :disabled="stillLoading"
                      @change="onLogoChange"
                      ref="logo"
                    />
                    <div v-if="error.logo" class="logo-error">
                      {{ $t(error.logo) }}
                    </div>
                  </div>

                  <h4 class="mg-bottom-md mg-top">
                    {{ $t("settings.documents") }}
                  </h4>
                  <NsComboBox
                    v-model="expireDefault"
                    :title="$t('settings.expire_default')"
                    :label="$t('settings.choose_expiration')"
                    :options="expireOptions"
                    :invalid-message="$t(error.expire_default)"
                    :disabled="stillLoading"
                    class="mg-bottom maxwidth"
                    ref="expire_default"
                  />
                  <NsComboBox
                    v-model="expireMax"
                    :title="$t('settings.expire_max')"
                    :label="$t('settings.choose_expiration')"
                    :options="expireOptions"
                    :helper-text="$t('settings.expire_max_helper')"
                    :invalid-message="$t(error.expire_max)"
                    :disabled="stillLoading"
                    class="mg-bottom maxwidth"
                    ref="expire_max"
                  />
                  <NsToggle
                    value="burnAfterReading"
                    :label="$t('settings.burn_after_reading_selected')"
                    v-model="isBurnAfterReadingSelected"
                    :disabled="stillLoading"
                    class="mg-bottom"
                  >
                    <template #tooltip>
                      {{ $t("settings.burn_after_reading_selected_tooltip") }}
                    </template>
                    <template slot="text-left">{{
                      $t("settings.disabled")
                    }}</template>
                    <template slot="text-right">{{
                      $t("settings.enabled")
                    }}</template>
                  </NsToggle>
                  <NsToggle
                    value="discussion"
                    :label="$t('settings.discussion')"
                    v-model="isDiscussionEnabled"
                    :disabled="stillLoading"
                    class="mg-bottom"
                  >
                    <template slot="text-left">{{
                      $t("settings.disabled")
                    }}</template>
                    <template slot="text-right">{{
                      $t("settings.enabled")
                    }}</template>
                  </NsToggle>
                  <NsToggle
                    v-if="isDiscussionEnabled"
                    value="openDiscussion"
                    :label="$t('settings.open_discussion')"
                    v-model="isOpenDiscussion"
                    :disabled="stillLoading"
                    class="mg-bottom"
                  >
                    <template slot="text-left">{{
                      $t("settings.disabled")
                    }}</template>
                    <template slot="text-right">{{
                      $t("settings.enabled")
                    }}</template>
                  </NsToggle>
                  <NsToggle
                    value="qrcode"
                    :label="$t('settings.qrcode')"
                    v-model="isQrcodeEnabled"
                    :disabled="stillLoading"
                    class="mg-bottom"
                  >
                    <template slot="text-left">{{
                      $t("settings.disabled")
                    }}</template>
                    <template slot="text-right">{{
                      $t("settings.enabled")
                    }}</template>
                  </NsToggle>

                  <h4 class="mg-bottom-md mg-top">
                    {{ $t("settings.attachments") }}
                  </h4>
                  <NsToggle
                    value="fileUpload"
                    :label="$t('settings.file_upload')"
                    v-model="isFileUploadEnabled"
                    :disabled="stillLoading"
                    class="mg-bottom"
                  >
                    <template #tooltip>
                      {{ $t("settings.file_upload_tooltip") }}
                    </template>
                    <template slot="text-left">{{
                      $t("settings.disabled")
                    }}</template>
                    <template slot="text-right">{{
                      $t("settings.enabled")
                    }}</template>
                  </NsToggle>
                  <template v-if="isFileUploadEnabled">
                    <NsSlider
                      v-model="sizeLimit"
                      :label="$t('settings.size_limit')"
                      min="1"
                      max="50"
                      step="1"
                      stepMultiplier="5"
                      minLabel=""
                      maxLabel=""
                      :unitLabel="$t('settings.mib')"
                      :invalidMessage="$t(error.size_limit)"
                      :disabled="stillLoading"
                      class="mg-bottom maxwidth"
                      ref="size_limit"
                    />
                    <NsInlineNotification
                      kind="info"
                      :title="$t('settings.size_limit_info_title')"
                      :description="$t('settings.size_limit_info_description')"
                      :showCloseButton="false"
                    />
                  </template>

                  <h4 class="mg-bottom-md mg-top">
                    {{ $t("settings.languages") }}
                  </h4>
                  <NsComboBox
                    v-model="languageDefault"
                    :title="$t('settings.language_default')"
                    :label="$t('settings.choose_language')"
                    :options="languageOptions"
                    :autoFilter="true"
                    :autoHighlight="true"
                    :helper-text="$t('settings.language_default_helper')"
                    :invalid-message="$t(error.language_default)"
                    :disabled="stillLoading"
                    class="mg-bottom maxwidth"
                    ref="language_default"
                  />
                  <NsToggle
                    value="languageSelection"
                    :label="$t('settings.language_selection')"
                    v-model="isLanguageSelectionEnabled"
                    :disabled="stillLoading"
                    class="mg-bottom"
                  >
                    <template #tooltip>
                      {{ $t("settings.language_selection_tooltip") }}
                    </template>
                    <template slot="text-left">{{
                      $t("settings.disabled")
                    }}</template>
                    <template slot="text-right">{{
                      $t("settings.enabled")
                    }}</template>
                  </NsToggle>
                </template>
              </cv-accordion-item>
            </cv-accordion>
            <NsInlineNotification
              v-if="error.configureModule"
              kind="error"
              :title="$t('action.configure-module')"
              :description="error.configureModule"
              :showCloseButton="false"
            />
            <NsInlineNotification
              v-if="validationErrorDetails.length"
              kind="error"
              :title="core.$t('apps_lets_encrypt.cannot_obtain_certificate')"
              :showCloseButton="false"
            >
              <template #description>
                <div class="flex flex-col gap-2">
                  <div
                    v-for="(detail, index) in validationErrorDetails"
                    :key="index"
                  >
                    {{ detail }}
                  </div>
                </div>
              </template>
            </NsInlineNotification>
            <NsButton
              kind="primary"
              :icon="Save20"
              :loading="loading.configureModule"
              :disabled="stillLoading"
              >{{ $t("settings.save") }}</NsButton
            >
          </cv-form>
        </cv-tile>
      </cv-column>
    </cv-row>
  </cv-grid>
</template>

<script>
import to from "await-to-js";
import { mapState } from "vuex";
import Reset20 from "@carbon/icons-vue/es/reset/20";
import {
  QueryParamService,
  UtilService,
  TaskService,
  IconService,
  PageTitleService,
} from "@nethserver/ns8-ui-lib";

const EXPIRE_VALUES = [
  "5min",
  "10min",
  "1hour",
  "1day",
  "1week",
  "1month",
  "1year",
  "never",
];

// PrivateBin 2.1 translations, labels in their own language
const LANGUAGES = {
  ar: "العربية",
  bg: "български език",
  ca: "català",
  co: "corsu",
  cs: "čeština",
  de: "Deutsch",
  el: "ελληνικά",
  en: "English",
  es: "español",
  et: "eesti",
  fa: "فارسی",
  fi: "suomi",
  fr: "français",
  he: "עברית",
  hi: "हिन्दी",
  hu: "magyar",
  id: "bahasa Indonesia",
  it: "italiano",
  ja: "日本語",
  jbo: "jbobau",
  ko: "한국어",
  ku: "Kurdî",
  la: "lingua latina",
  lt: "lietuvių kalba",
  nl: "Nederlands",
  no: "Norsk",
  oc: "occitan",
  pl: "polski",
  pt: "português",
  ro: "limba română",
  ru: "Русский",
  sk: "slovenčina",
  sl: "slovenščina",
  sv: "svenska",
  th: "ไทย",
  tr: "Türkçe",
  uk: "українська мова",
  zh: "中文",
  "zh-tw": "繁體中文",
};

const LOGO_MAX_BYTES = 512 * 1024;

export default {
  name: "Settings",
  mixins: [
    TaskService,
    IconService,
    UtilService,
    QueryParamService,
    PageTitleService,
  ],
  pageTitle() {
    return this.$t("settings.title") + " - " + this.appName;
  },
  data() {
    return {
      q: {
        page: "settings",
      },
      Reset20,
      status: {},
      validationErrorDetails: [],
      toggleAccordion: [false],
      urlCheckInterval: null,
      host: "",
      configuredHost: "",
      isLetsEncryptEnabled: false,
      isLetsEncryptCurrentlyEnabled: false,
      isRouteConfigured: true,
      name: "",
      notice: "",
      info: "",
      isLogoSet: false,
      isLogoReset: false,
      logoData: "",
      logoPreview: "",
      logoUploaderKey: 0,
      // empty until the configuration loads: NsComboBox shows the label only when the value changes.
      // Its options stay fixed: new options are filtered by the old label and the new value is lost.
      expireDefault: "",
      expireMax: "",
      languageDefault: "",
      isDiscussionEnabled: false,
      isOpenDiscussion: false,
      isBurnAfterReadingSelected: false,
      isQrcodeEnabled: true,
      isFileUploadEnabled: false,
      sizeLimit: "10",
      isLanguageSelectionEnabled: true,
      isPrivateCreators: true,
      loading: {
        getConfiguration: false,
        configureModule: false,
        getStatus: false,
      },
      error: {
        getConfiguration: "",
        configureModule: "",
        getStatus: "",
        host: "",
        lets_encrypt: "",
        name: "",
        notice: "",
        info: "",
        logo: "",
        expire_default: "",
        expire_max: "",
        size_limit: "",
        language_default: "",
      },
    };
  },
  computed: {
    ...mapState(["instanceName", "core", "appName"]),
    stillLoading() {
      return (
        this.loading.getConfiguration ||
        this.loading.configureModule ||
        this.loading.getStatus
      );
    },
    isRouteMissing() {
      // a first configuration has no route yet: only a saved host without route means a clone
      return (
        !this.loading.getConfiguration &&
        this.configuredHost &&
        !this.isRouteConfigured
      );
    },
    expireOptions() {
      return EXPIRE_VALUES.map((value) => ({
        name: value,
        label: this.$t("settings.expire_" + value),
        value,
      }));
    },
    languageOptions() {
      const auto = {
        name: "auto",
        label: this.$t("settings.language_auto"),
        value: "auto",
      };
      const languages = Object.entries(LANGUAGES).map(([value, label]) => ({
        name: value,
        label,
        value,
      }));
      return [auto, ...languages];
    },
  },
  created() {
    this.getConfiguration();
    this.getStatus();
  },
  beforeRouteEnter(to, from, next) {
    next((vm) => {
      vm.watchQueryData(vm);
      vm.urlCheckInterval = vm.initUrlBindingForApp(vm, vm.q.page);
    });
  },
  beforeRouteLeave(to, from, next) {
    clearInterval(this.urlCheckInterval);
    next();
  },
  methods: {
    goToCertificates() {
      this.core.$router.push("/settings/tls-certificates");
    },
    openAdvancedFor(field) {
      // a hidden field cannot show its error nor take the focus
      if (!["host", "lets_encrypt"].includes(field)) {
        this.$set(this.toggleAccordion, 0, true);
      }
    },
    onLogoChange(files) {
      this.error.logo = "";
      const item = files.length ? files[files.length - 1] : null;
      if (!item) {
        return;
      }
      const file = item.file;
      if (!["image/png", "image/jpeg"].includes(file.type)) {
        this.error.logo = "settings.logo_invalid_format";
        return;
      }
      if (file.size > LOGO_MAX_BYTES) {
        this.error.logo = "settings.logo_too_large";
        return;
      }
      const reader = new FileReader();
      reader.onload = () => {
        this.logoPreview = reader.result;
        this.logoData = reader.result.split(",")[1];
        this.isLogoReset = false;
      };
      reader.readAsDataURL(file);
    },
    resetLogo() {
      this.logoData = "";
      this.logoPreview = "";
      this.isLogoReset = this.isLogoSet;
      this.error.logo = "";
      this.logoUploaderKey++;
    },
    async getStatus() {
      this.loading.getStatus = true;
      this.error.getStatus = "";
      const taskAction = "get-status";
      const eventId = this.getUuid();
      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.getStatusAborted
      );
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.getStatusCompleted
      );
      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          extra: {
            title: this.$t("action." + taskAction),
            isNotificationHidden: true,
            eventId,
          },
        })
      );
      const err = res[0];
      if (err) {
        console.error(`error creating task ${taskAction}`, err);
        this.error.getStatus = this.getErrorMessage(err);
        this.loading.getStatus = false;
        return;
      }
    },
    getStatusAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.getStatus = this.$t("error.generic_error");
      this.loading.getStatus = false;
    },
    getStatusCompleted(taskContext, taskResult) {
      this.status = taskResult.output;
      this.loading.getStatus = false;
    },
    async getConfiguration() {
      this.loading.getConfiguration = true;
      this.error.getConfiguration = "";
      const taskAction = "get-configuration";
      const eventId = this.getUuid();
      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.getConfigurationAborted
      );
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.getConfigurationCompleted
      );
      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          extra: {
            title: this.$t("action." + taskAction),
            isNotificationHidden: true,
            eventId,
          },
        })
      );
      const err = res[0];
      if (err) {
        console.error(`error creating task ${taskAction}`, err);
        this.error.getConfiguration = this.getErrorMessage(err);
        this.loading.getConfiguration = false;
        return;
      }
    },
    getConfigurationAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.getConfiguration = this.$t("error.generic_error");
      this.loading.getConfiguration = false;
    },
    getConfigurationCompleted(taskContext, taskResult) {
      const config = taskResult.output;
      this.host = config.host;
      this.configuredHost = config.host;
      this.isLetsEncryptEnabled = config.lets_encrypt;
      this.isLetsEncryptCurrentlyEnabled = config.lets_encrypt;
      this.isRouteConfigured = config.route_configured;
      this.name = config.name;
      this.notice = config.notice;
      this.info = config.info;
      this.isLogoSet = config.logo_set;
      this.isLogoReset = false;
      this.logoData = "";
      this.logoPreview = "";
      this.logoUploaderKey++;
      this.expireMax = config.expire_max;
      this.expireDefault = config.expire_default;
      this.languageDefault = config.language_default;
      this.isDiscussionEnabled = config.discussion;
      this.isOpenDiscussion = config.open_discussion;
      this.isBurnAfterReadingSelected = config.burn_after_reading_selected;
      this.isQrcodeEnabled = config.qrcode;
      this.isFileUploadEnabled = config.file_upload;
      this.sizeLimit = String(config.size_limit);
      this.isLanguageSelectionEnabled = config.language_selection;
      this.isPrivateCreators = config.private_creators;

      this.loading.getConfiguration = false;
      this.focusElement("host");
    },
    validateConfigureModule() {
      this.clearErrors(this);
      this.validationErrorDetails = [];
      let isValidationOk = true;

      const fail = (field, message) => {
        this.error[field] = message;
        this.openAdvancedFor(field);
        if (isValidationOk) {
          this.focusElement(field);
        }
        isValidationOk = false;
      };

      if (!this.host) {
        fail("host", "common.required");
      }
      if (!this.expireMax) {
        fail("expire_max", "common.required");
      }
      if (!this.expireDefault) {
        fail("expire_default", "common.required");
      }
      if (
        this.expireDefault &&
        this.expireMax &&
        EXPIRE_VALUES.indexOf(this.expireDefault) >
          EXPIRE_VALUES.indexOf(this.expireMax)
      ) {
        fail("expire_default", "settings.expire_default_above_max");
      }
      if (!this.languageDefault) {
        fail("language_default", "common.required");
      }
      return isValidationOk;
    },
    configureModuleValidationFailed(validationErrors) {
      this.loading.configureModule = false;
      let focusAlreadySet = false;
      for (const validationError of validationErrors) {
        const param = validationError.parameter;
        if (validationError.details) {
          this.validationErrorDetails = validationError.details
            .split("\n")
            .filter((detail) => detail.trim() !== "");
        } else {
          this.error[param] = "settings." + validationError.error;
          this.openAdvancedFor(param);
          if (!focusAlreadySet && param !== "logo") {
            this.focusElement(param);
            focusAlreadySet = true;
          }
        }
      }
    },
    async configureModule() {
      if (!this.validateConfigureModule()) {
        return;
      }

      this.loading.configureModule = true;
      const taskAction = "configure-module";
      const eventId = this.getUuid();
      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.configureModuleAborted
      );
      this.core.$root.$once(
        `${taskAction}-validation-failed-${eventId}`,
        this.configureModuleValidationFailed
      );
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.configureModuleCompleted
      );

      const data = {
        host: this.host,
        lets_encrypt: this.isLetsEncryptEnabled,
        name: this.name,
        notice: this.notice,
        info: this.info,
        expire_default: this.expireDefault,
        expire_max: this.expireMax,
        discussion: this.isDiscussionEnabled,
        open_discussion: this.isDiscussionEnabled && this.isOpenDiscussion,
        burn_after_reading_selected: this.isBurnAfterReadingSelected,
        qrcode: this.isQrcodeEnabled,
        file_upload: this.isFileUploadEnabled,
        size_limit: parseInt(this.sizeLimit, 10),
        language_selection: this.isLanguageSelectionEnabled,
        language_default: this.languageDefault,
        private_creators: this.isPrivateCreators,
      };
      // without the logo key the backend keeps the current logo
      if (this.logoData) {
        data.logo = this.logoData;
      } else if (this.isLogoReset) {
        data.logo = "";
      }

      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          data,
          extra: {
            title: this.$t("settings.instance_configuration", {
              instance: this.instanceName,
            }),
            description: this.$t("settings.configuring"),
            eventId,
          },
        })
      );
      const err = res[0];
      if (err) {
        console.error(`error creating task ${taskAction}`, err);
        this.error.configureModule = this.getErrorMessage(err);
        this.loading.configureModule = false;
        return;
      }
    },
    configureModuleAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.configureModule = this.$t("error.generic_error");
      this.loading.configureModule = false;
    },
    configureModuleCompleted() {
      this.loading.configureModule = false;
      this.getConfiguration();
    },
  },
};
</script>

<style scoped lang="scss">
@import "../styles/carbon-utils";

.mg-bottom {
  margin-bottom: $spacing-06;
}

.mg-bottom-md {
  margin-bottom: $spacing-05;
}

.mg-bottom-sm {
  margin-bottom: $spacing-03;
}

.mg-top {
  margin-top: $spacing-07;
}

.maxwidth {
  max-width: 38rem;
}

.logo-row {
  display: flex;
  align-items: center;
  gap: $spacing-05;
}

.logo-preview {
  height: 38px;
}

.logo-error {
  color: $danger-01;
  font-size: 0.75rem;
  margin-top: $spacing-02;
}
</style>
